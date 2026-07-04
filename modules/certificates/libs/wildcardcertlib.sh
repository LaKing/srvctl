#!/bin/bash

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
