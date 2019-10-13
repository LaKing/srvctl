#!/bin/bash

function check_pem { ## file
    
    local pem
    pem="$1"
    
    if [[ -f "$pem" ]]
    then
        if openssl x509 -checkend 604800 -noout -in "$pem"
        then
            #dbg "$cert_pem OK"
            echo 0 > /dev/null
        else
            msg "Certificate has expired or will do so within a week! $pem"
            rm -rf "$pem"
        fi
    fi
    
}

## create selfsigned certificate the hard way
function create_selfsigned_domain_certificate { ## for domain on path
    
    msg "create_selfsigned_domain_certificate $1"
    
    local domain cert_path
    
    domain="$1"
    cert_path="$2"
    
    if [[ -z "$domain" ]]
    then
        err "No domain specified to create certificate"
        return
    fi
    
    if [[ -z "$cert_path" ]]
    then
        err "No cert_path specified"
        return
    fi
    
    mkdir -p "$cert_path"
    
    ssl_days=3650
    
    ## configuration files
    ssl_random="$cert_path/random.txt"
    ssl_config="$cert_path/config.txt"
    ssl_extfile="$cert_path/extfile.txt"
    
    ## key unencrypted
    ssl_key="$cert_path/$domain.key"
    ## key encrypted
    ssl_org="$cert_path/$domain.key.org"
    
    ## certificate signing request
    ssl_csr="$cert_path/$domain.csr"
    
    ## the self signed certificate
    ssl_crt="$cert_path/$domain.crt"
    
    ## dhparams
    ssl_dhparams="$cert_path/dhparam"
    
    ## THE CERTIFICATE - overwrite with:
    ## key
    ## CA signed crt
    ssl_pem="$cert_path/$domain.pem"
    ssl_cab="$cert_path/ca-bundle.pem"
    
    if [[ ! -f $ssl_cab ]]
    then
        ssl_cab=''
    fi
    
    if [[ -f $ssl_pem ]] && [[ ! -z "$(cat "$ssl_pem")" ]]
    then
        
        if run openssl x509 -checkend 604800 -noout -in "$ssl_pem"
        then
            run openssl verify -CAfile "$ssl_pem $ssl_pem" > /dev/null
            if [[ "$?" == "2" ]]
            then
                #ntc "$domain already has a Self signed certificate!"
                return
            else
                if run openssl verify -CAfile "$ssl_pem" -verify_hostname "$domain" "$ssl_pem" > /dev/null
                then
                    if [[ ! -f $ssl_key ]]
                    then
                        err "Domain $domain has certificate, but no key-file! $ssl_key ?"
                        exit 46
                    fi
                    cat "$ssl_pem" > "$cert_path/cert.pem"
                    msg "$domain has a valid certificate."
                    return
                fi
                
            fi
        else
            ntc "$domain certificate invalid or will expire soon! $ssl_pem"
        fi
    fi
    
    if [[ -f $ssl_crt ]] || [[ -f $ssl_pem ]]
    then
        ntc "Remove $cert_path manually to create a new certificate."
        ntc "Certificate files must be: $ssl_key $ssl_crt"
        ls "$cert_path"
        return
    fi
    
    if [[ -z "$ssl_password" ]]
    then
        
        ssl_password="$(new_password)"
    fi
    
    msg "Create certificate for $domain."
    
    mkdir -p "$cert_path"
    
        cat > "$ssl_config" << EOF
        ## $SRVCTL generated config file

        RANDFILE               = $ssl_random

        [ req ]
        prompt                 = no
        string_mask            = utf8only
        default_bits           = 2048
        default_keyfile        = keyfile.pem
        distinguished_name     = req_distinguished_name

        req_extensions         = v3_req

        output_password        = $ssl_password

        [ req_distinguished_name ]
        CN                     = $domain
        emailAddress           = webmaster@$domain

EOF
    
    
        cat > "$ssl_extfile" << EOF
        [ v3_req ]
        basicConstraints = critical,CA:FALSE
        keyUsage = keyEncipherment, dataEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names
        [alt_names]
        DNS.1 = $domain
        DNS.2 = *.$domain
EOF
    
    
    cat "$ssl_extfile" >> "$ssl_config"
    
    #### create certificate
    
    ## Generate a Private Key
    run openssl genrsa -des3 -passout pass:"$ssl_password" -out "$ssl_key" 2048 2> /dev/null
    
    ## Generate a CSR (Certificate Signing Request)
    run openssl req -new -passin pass:"$ssl_password" -passout pass:"$ssl_password" -key "$ssl_key" -out "$ssl_csr" -days "$ssl_days" -config "$ssl_config" 2> /dev/null
    
    ## Remove Passphrase from Key
    run cp "$ssl_key" "$ssl_org"
    run openssl rsa -passin pass:"$ssl_password" -in "$ssl_org" -out "$ssl_key" 2> /dev/null
    
    ## Self-Sign Certificate
    run openssl x509 -req -days "$ssl_days" -passin pass:"$ssl_password" -extensions v3_req -extfile "$ssl_extfile" -in "$ssl_csr" -signkey "$ssl_key" -out "$ssl_crt" 2> /dev/null
    
    ## some services - like perdition - may require dhparams added to the crt
    if [[ ! -f $ssl_dhparams ]]
    then
        run openssl dhparam -out "$ssl_dhparams" 1024
    fi
    
    cat "$ssl_dhparams" >> "$ssl_crt"
    
    ## create a certificate chainfile in pem format
    cat "$ssl_key" >  "$ssl_pem"
    cat "$ssl_crt" >> "$ssl_pem"
    
    ## cert.pem - ready to use certificate chain for cert
    ## key
    ## CA signed crt
    ## ca-bundle
    cat "$ssl_pem" > "$cert_path/cert.pem"
}


