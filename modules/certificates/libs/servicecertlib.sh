#!/bin/bash

##
##   certificates/libs/servicecertlib.sh — host certificate for a local
##   service directory (install_service_hostcertificate PATH).
##
##   Sourced by load_libs whenever the certificates module is enabled.
##   Called by gui, postfix and perdition update-install code with e.g.
##   /etc/postfix. Picks a certificate dir under /etc/srvctl/cert/ in this
##   order (first hit wins):
##     1. $SC_COMPANY_DOMAIN
##     2. ${HOSTNAME:3}  (hostname with its two-character prefix stripped)
##     3. $HOSTNAME
##     4. first glob-ordered subdir that has matching pem+key
##     5. freshly generated self-signed cert for $HOSTNAME
##   Writes $PATH/crt.pem (pem with dhparam appended), $PATH/key.pem and,
##   when present, $PATH/ca-bundle.pem — all chmod 400. The dhparam file
##   is cached as $src/dhparam next to the source certificate.
##

## A usable private key for $dom under $src: a separate <dom>.key, else a key
## EMBEDDED in a combined <dom>.pem (cert+chain+key, e.g. the haproxy-style pem
## an admin drops in /etc/srvctl/cert/<dom>/). Prints the key PEM; non-zero if
## neither yields one. Lets ONE combined pem serve both haproxy and the mail/
## gui services instead of also requiring a separate .key.
function service_key_pem { ## src dom
    local src="$1" dom="$2" key=""
    if [[ -f "$src/$dom.key" ]]
    then
        key="$(cat "$src/$dom.key")"
    elif [[ -f "$src/$dom.pem" ]]
    then
        key="$(openssl pkey -in "$src/$dom.pem" 2> /dev/null)"
    fi
    [[ -n "$key" ]] || return 1
    printf '%s\n' "$key"
}

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
        
        if [[ -f "$src/$dom.pem" ]] && service_key_pem "$src" "$dom" > /dev/null
        then
            found=true
        fi
    fi
    
    
    if ! $found
    then
        ## by convention multi-server configurations should prefix hostnames with two characters
        src="/etc/srvctl/cert/${HOSTNAME:3}"
        dom="${HOSTNAME:3}"
        
        if [[ -f "$src/$dom.pem" ]] && service_key_pem "$src" "$dom" > /dev/null
        then
            found=true
        fi
    fi
    
    if ! $found
    then
        
        ## we may have one referring to the HOSTNAME directly
        src="/etc/srvctl/cert/$HOSTNAME"
        dom="$HOSTNAME"
        
        if [[ -f "$src/$dom.pem" ]] && service_key_pem "$src" "$dom" > /dev/null
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
                    if [[ -f "$src/$dom.pem" ]] && service_key_pem "$src" "$dom" > /dev/null
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
        if [[ -f "$src/$dom.pem" ]] && service_key_pem "$src" "$dom" > /dev/null
        then
            found=true
        fi
    fi
    
    if $found
    then
        
        ## some services - like perdition - may require dhparams added to the crt
        ssl_dhparams="$src/dhparam"

        if [[ ! -f $ssl_dhparams ]]
        then
            ## FIXME(v4): 1024-bit DH parameters are Logjam-weak and rejected
            ## by modern TLS stacks; bump deliberately in v4 (cached file!).
            run openssl dhparam -out "$ssl_dhparams" 1024
        fi
        
        cat "$src/$dom.pem" > "$path/crt.pem"
        service_key_pem "$src" "$dom" > "$path/key.pem"
        cat "$ssl_dhparams" >> "$path/crt.pem"
        
        if [[ -f $src/ca-bundle.pem ]]
        then
            cat "$src/ca-bundle.pem" > "$path/ca-bundle.pem"
        fi
        msg "Imported $dom certificate for $path"
        
    else
        err "ERROR Could not locate a certificate for $path"
        ## FIXME(v4): bare 'exit' exits with the status of err (0), so this
        ## hard failure terminates the srvctl run with exit code 0, masking
        ## the error from update-install wrappers and cron.
        exit
    fi
    
    if [[ -f $path/ca-bundle.pem ]]
    then
        chmod 400 "$path/ca-bundle.pem"
    fi
    chmod 400 "$path/crt.pem"
    chmod 400 "$path/key.pem"
    
}
