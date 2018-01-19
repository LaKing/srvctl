#!/bin/bash

function install_service_hostcertificate() { ## path
    ## create crt.key, pem, .. and bundle
    local path src dom found
    ## usually /etc/$service
    path="$1"
    
    mkdir -p /etc/srvctl/cert
    
    if [[ -f $path/crt.pem ]] && [[ -f $path/key.pem ]]
    then
        return
    fi
    
    found=false
    
    
    msg "Host has no certificates in $path"
    if [[ -z "$(ls /etc/srvctl/cert)" ]]
    then
        msg "There are no host-service certificates. Use a CA signed certificate in production!"
        create_selfsigned_domain_certificate "$HOSTNAME" "/etc/srvctl/cert/$HOSTNAME"
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
        
        ## we may one referring to the HOSTNAME directly
        src="/etc/srvctl/cert/$HOSTNAME"
        dom="$HOSTNAME"
        
        if [[ -f "$src/$dom.pem" ]] && [[ -f "$src/$dom.key" ]]
        then
            found=true
        fi
    fi
    
    for dir in /etc/srvctl/cert/*
    do
        
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
        
    done
    
    
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
        err "ERROR Could not locate certificate for $path"
    fi
    
    
    chmod 400 /etc/perdition/crt.pem
    chmod 400 /etc/perdition/key.pem
    
}
