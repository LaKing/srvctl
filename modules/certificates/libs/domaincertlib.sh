#!/bin/bash

##
##   certificates/libs/domaincertlib.sh — per-domain certificate helpers.
##
##   Sourced by load_libs whenever the certificates module is enabled.
##   Provides:
##     check_pem PEM                              — expiry check + prune
##     create_selfsigned_domain_certificate D P   — self-signed wildcard-SAN
##
##   Consumers: haproxy (check_pem via proxylib.sh), containers
##   (create_selfsigned_domain_certificate for /srv/$C/cert) and
##   servicecertlib.sh in this module (self-signed fallback).
##
##   The ssl_* variables are deliberately NOT local: the same global names
##   are a shared convention with other modules (e.g. codepad), and a
##   pre-set $ssl_password is honored on purpose.
##

## check_pem: if the pem expires within 7 days (604800 s), print its
## details and DELETE the file. Always returns 0 — haproxy's
## load_certificate_folder_files (proxylib.sh) relies on the deletion
## side effect plus its own -f re-check, not on the return value.
## Despite the historical "unused" annotation this function is load-bearing.
## FIXME(v4): returns 0 unconditionally, so the caller's 'if check_pem' is
## decorative; keep the delete-then-recheck semantics if this ever changes.
function check_pem { ## file

    local pem
    local cert_subject cert_issuer cert_start cert_end reason
    pem="$1"

    if [[ -f "$pem" ]]
    then
        if openssl x509 -checkend 604800 -noout -in "$pem" > /dev/null
        then
            ## certificate is valid long enough — deliberate no-op
            echo 0 > /dev/null
        else
            # Get details before removal
            cert_subject=$(openssl x509 -noout -subject -in "$pem" 2>/dev/null | sed 's/subject=//')
            cert_issuer=$(openssl x509 -noout -issuer  -in "$pem" 2>/dev/null | sed 's/issuer=//')
            cert_start=$(openssl x509 -noout -startdate -in "$pem" 2>/dev/null | sed 's/notBefore=//')
            cert_end=$(openssl x509 -noout -enddate   -in "$pem" 2>/dev/null | sed 's/notAfter=//')
    
            # Determine if it's already expired or just expiring soon
            if openssl x509 -checkend 0 -noout -in "$pem" > /dev/null 2>&1; then
                reason="expires within 7 days"
            else
                reason="already EXPIRED"
            fi
    
            msg "Certificate check failed ($reason): $pem"
            msg "  Subject : $cert_subject"
            msg "  Issuer  : $cert_issuer"
            msg "  Valid   : $cert_start  ->  $cert_end"
            msg "  Removing file."
            rm -rf "$pem"
        fi
    fi
    
}

## create selfsigned certificate the hard way
## Layout produced in $2 (all names are API for haproxy/containers):
##   $domain.key (unencrypted), $domain.key.org (encrypted), $domain.csr,
##   $domain.crt, $domain.pem = key first then crt, cert.pem = copy of it,
##   plus config.txt / extfile.txt / random.txt scratch files.
## RSA 2048, 3650 days, CN=$domain, SAN DNS:$domain + DNS:*.$domain.
## If a still-valid $domain.pem exists, it is kept (exit 46 when the cert
## exists without its key file).
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
    
    ## THE CERTIFICATE - overwrite with:
    ## key
    ## CA signed crt
    ssl_pem="$cert_path/$domain.pem"

    ## ca-bundle path — computed but not used anywhere in this function;
    ## the global may be read by other code, so it is kept as-is (v4 decides).
    ssl_cab="$cert_path/ca-bundle.pem"

    if [[ ! -f $ssl_cab ]]
    then
        ssl_cab=''
    fi

    if [[ -f $ssl_pem ]] && [[ -n "$(cat "$ssl_pem")" ]]
    then
        
        if run openssl x509 -checkend 604800 -noout -in "$ssl_pem"
        then
            ## FIXME(v4): "$ssl_pem $ssl_pem" only works because run
            ## word-splits its arguments, and exit code 2 means verification
            ## FAILED (e.g. a CA-signed leaf), not "self-signed": CA-signed
            ## certs take this early return without refreshing cert.pem or
            ## checking the key file, and log a spurious ERROR via run/eyif.
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
    
    ## throwaway passphrase for the key (stripped again below); a pre-set
    ## global ssl_password is honored on purpose
    if [[ -z "$ssl_password" ]]
    then

        ssl_password="$(new_password)"
    fi

    msg "Create certificate for $domain."

    mkdir -p "$cert_path"

    ## Note: the heredoc bodies below keep their 8-space leading indentation
    ## on purpose — the OpenSSL CONF parser tolerates it, and the generated
    ## config.txt/extfile.txt bytes are part of the module's behavior.
    ## FIXME(v4): the passphrase is persisted in config.txt (output_password)
    ## and echoed on openssl command lines by run — secret-material leakage
    ## into on-disk files, terminal scrollback and ps-visible argv.
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
    
    #keyUsage = nonRepudiation, digitalSignature, keyEncipherment
    
    ## this causes chrome to fail with ERR_SSL_KEY_USAGE_INCOMPATIBLE
    #keyUsage = keyEncipherment, dataEncipherment
    
        cat > "$ssl_extfile" << EOF
        [ v3_req ]
        basicConstraints = critical,CA:FALSE
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names
        keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
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
    
    ## create a certificate chainfile in pem format — key first, then crt
    ## (order matters: haproxy loads the combined pem)
    ## FIXME(v4): both combined pems contain the private key but are created
    ## with the default umask (0644, no chmod); confidentiality relies on
    ## parent-directory modes set elsewhere (set_permissions at update-install).
    cat "$ssl_key" >  "$ssl_pem"
    cat "$ssl_crt" >> "$ssl_pem"

    ## cert.pem - ready to use certificate chain for cert
    ## key
    ## CA signed crt
    ## ca-bundle
    cat "$ssl_pem" > "$cert_path/cert.pem"
}
