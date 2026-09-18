#!/bin/bash

##
##   certificates/libs/wildcardcertlib.sh — wildcard certificate fan-out.
##
##   Sourced by load_libs whenever the certificates module is enabled.
##   apply_wildcard_certificates copies
##   admin-installed wildcard certs from /etc/srvctl/cert/*/ into
##   $SC_DATASTORE_DIR/cert/<container>.pem for every matching container.
##   Only entry point: this module's regenerate_certificates hook
##   (invoked by the haproxy and named modules).
##

## check_wildcard_pem (the admin wildcard rule) lives in wildcardgatelib.sh,
## shared with certselect and the letsencrypt http-01 gate.

## apply_wildcard_certificates: for every /etc/srvctl/cert/*/*.pem that is
## a valid wildcard cert, copy it to $SC_DATASTORE_DIR/cert/$c.pem for each
## container $c (from 'get cluster container_list') matching *.domain or
## the bare domain. Target file names are API for the container side.
function apply_wildcard_certificates() {

    msg "Apply wildcard certificates"

    ## Ensure the datastore cert dir exists before the fan-out writes into it —
    ## on a fresh datastore it is created later (regenerate_haproxy_conf), so the
    ## first fan-out used to silently no-op.
    mkdir -p "$SC_DATASTORE_DIR/cert"

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
                    ## The copy contains the private key — keep it non-readable.
                    cat "$i" > "$SC_DATASTORE_DIR/cert/$c.pem"
                    chmod 600 "$SC_DATASTORE_DIR/cert/$c.pem"
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
