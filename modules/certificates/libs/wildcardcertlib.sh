#!/bin/bash

function check_wildcared_pem { ## file
    
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
            fi
        fi
    fi
    
    echo false
}

function apply_wildcard_certificates() {
    
    for i in /etc/srvctl/cert/*/*.pem
    do
        checked_domain="$(check_wildcared_pem "$i")"
        
        if [[ "$checked_domain" != false ]]
        then
            msg "Apply wildcard certificate $checked_domain"
            
            for c in $(get cluster container_list)
            do
                
                ## check the domains we have a wildcard certificate for
                if [[ $c == *".$checked_domain" ]]
                then
                    ## create a copy of the cert in the datastore cert dir
                    cat "$i" > "$SC_DATASTORE_DIR/cert/$c.pem"
                fi
                
                ## check the containers against company domains that have no hostname
                if [[ $c == "$SC_COMPANY_DOMAIN" ]] && [[ ${c} != *"."* ]]
                then
                    cat "$i" > "$SC_DATASTORE_DIR/cert/$c.$SC_COMPANY_DOMAIN.pem"
                fi
                
            done
            
        fi
        
    done
}

## TODO
## rather delete haproxy certs then creating copies
## check how we could use ipv6 with certificates without publishing them to containers