#!/bin/bash

function install_service_hostcertificate() { ## path
    ## create crt.key, pem, .. and bundle
    local path src dom found
    ## usually /etc/$service
    path="$1"
    
    mkdir -p /etc/srvctl/cert
    
    if [[ -f $path/crt.pem ]] && [[ -f $path/key.pem ]]
    then
        msg "Host has certificates in $path"
    else
        msg "Host has NO certificate in $path"
    fi
    
    found=false
    
    if ! $found
    then
        ## check SC_COMPANY_DOMAIN first
        src="/etc/srvctl/cert/$SC_COMPANY_DOMAIN"
        dom="$SC_COMPANY_DOMAIN"
        
        if [[ -f "$src/$dom.pem" ]] && [[ -f "$src/$dom.key" ]]
        then
            found=true
        fi
    fi
    
    
    if ! $found
    then
        ## by convention multi-server configurations should prefix hostnames with two charcaters
        src="/etc/srvctl/cert/${HOSTNAME:3}"
        dom="${HOSTNAME:3}"
        
        if [[ -f "$src/$dom.pem" ]] && [[ -f "$src/$dom.key" ]]
        then
            found=true
        fi
    fi
    
    if ! $found
    then
        
        ## we may have one referring to the HOSTNAME directly
        src="/etc/srvctl/cert/$HOSTNAME"
        dom="$HOSTNAME"
        
        if [[ -f "$src/$dom.pem" ]] && [[ -f "$src/$dom.key" ]]
        then
            found=true
        fi
    fi
    
    if ! $found
    then
        ## get any certificate from cert dir
        for dir in /etc/srvctl/cert/*
        do
            if [[ -d $dir ]]
            then
                d="${dir:17}"
                
                if ! $found
                then
                    src="$dir"
                    dom="$d"
                    if [[ -f "$src/$dom.pem" ]] && [[ -f "$src/$dom.key" ]]
                    then
                        found=true
                    fi
                fi
            fi
        done
    fi
    
    if ! $found
    then
        msg "Could not find certificates for $HOSTNAME. Use a CA signed certificate in production!"
        create_selfsigned_domain_certificate "$HOSTNAME" "/etc/srvctl/cert/$HOSTNAME"
        src="/etc/srvctl/cert/$HOSTNAME"
        dom="$HOSTNAME"
        if [[ -f "$src/$dom.pem" ]] && [[ -f "$src/$dom.key" ]]
        then
            found=true
        fi
    fi
    
    if $found
    then
        cat "$src/$dom.pem" > "$path/crt.pem"
        cat "$src/$dom.key" > "$path/key.pem"
        if [[ -f $src/ca-bundle.pem ]]
        then
            cat "$src/ca-bundle.pem" > "$path/ca-bundle.pem"
        fi
        msg "Imported $dom certificate for $path"
    else
        err "ERROR Could not locate a certificate for $path"
        exit
    fi
    
    if [[ -f $path/ca-bundle.pem ]]
    then
        chmod 400 "$path/ca-bundle.pem"
    fi
    chmod 400 "$path/crt.pem"
    chmod 400 "$path/key.pem"
    
}
