#!/bin/bash

##
##   certificates/libs/wildcardcertlib.sh — wildcard certificate fan-out.
##
##   Sourced by load_libs whenever the certificates module is enabled.
##   check_wildcard_pem inspects a pem; apply_wildcard_certificates copies
##   admin-installed wildcard certs from /etc/srvctl/cert/*/ into
##   $SC_DATASTORE_DIR/cert/<container>.pem for every matching container.
##   Only entry point: this module's regenerate_certificates hook
##   (invoked by the haproxy and named modules).
##

## check_wildcard_pem PEM: echo the wildcard base domain when the pem's
## first certificate is unexpired (7-day checkend) and its subject is a
## wildcard CN; otherwise echo the literal string "false". The echoed
## string is the protocol — callers compare against "false".
## Both subject spellings must stay supported:
## "subject=CN = *.X" (OpenSSL 1.x) and "subject=CN=*.X" (OpenSSL 3.x).
function check_wildcard_pem { ## file
    ## first certificate in pem file must be the certificate.
    
    local pem subject
    pem="$1"
    
    ## check if we have a valid argument
    if [[ -f "$pem" ]]
    then
        ## check if the certificate is not expired
        if openssl x509 -checkend 604800 -noout -in "$pem" > /dev/null
        then
            ## check if it is a wildcard certificate
            subject="$(openssl x509 -in "$pem" -noout --subject)"
            if [[ $subject == "subject=CN = *."* ]]
            then
                ## return the domain of the wildcard certificate
                echo "${subject:15}"
                return
            elif [[ $subject == "subject=CN=*."* ]]
            then
                ## OpenSSL 3.x format without spaces
                echo "${subject:13}"
                return
            fi
        fi
    fi
    
    echo false
}

## apply_wildcard_certificates: for every /etc/srvctl/cert/*/*.pem that is
## a valid wildcard cert, copy it to $SC_DATASTORE_DIR/cert/$c.pem for each
## container $c (from 'get cluster container_list') matching *.domain or
## the bare domain. Target file names are API for the container side.
function apply_wildcard_certificates() {

    msg "Apply wildcard certificates"
    
    for i in /etc/srvctl/cert/*/*.pem
    do
        checked_domain="$(check_wildcard_pem "$i")"
        
        msg "Check $i $checked_domain"
        
        if [[ "$checked_domain" != false ]]
        then
            msg "Apply wildcard certificate $checked_domain"
            
            for c in $(get cluster container_list)
            do
                
                ## check the domains we have a wildcard certificate for
                if [[ $c == *".$checked_domain" ]] || [[ $c == "$checked_domain" ]]
                then
                    ## create a copy of the cert in the datastore cert dir
                    ## FIXME(v4): $SC_DATASTORE_DIR/cert is never created by
                    ## this module — on a read-only datastore or before the
                    ## haproxy/letsencrypt mkdir this cat fails and wildcard
                    ## certs are silently not applied.
                    ## FIXME(v4): the copy contains the private key but is
                    ## written with the default umask (0644, no chmod).
                    cat "$i" > "$SC_DATASTORE_DIR/cert/$c.pem"
                fi

                ## check the containers against company domains that have no hostname
                ## FIXME(v4): self-contradictory condition — whenever
                ## SC_COMPANY_DOMAIN contains a dot (always in practice) it can
                ## never be true, so dot-less container names never receive the
                ## company wildcard cert; first operand was almost certainly
                ## meant to be $checked_domain.
                if [[ $c == "$SC_COMPANY_DOMAIN" ]] && [[ ${c} != *"."* ]]
                then
                    cat "$i" > "$SC_DATASTORE_DIR/cert/$c.$SC_COMPANY_DOMAIN.pem"
                fi
                
            done
            
        fi
        
    done
}
