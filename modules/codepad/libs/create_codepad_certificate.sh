#!/bin/bash

##
##   create_codepad_certificate ROOTFS — one-shot self-signed certificate
##   for the codepad template rootfs (localhost.key/csr/org.pem/crt plus
##   the openssl request config in /var/codepad/). CN and SANs are the
##   build HOST's $HOSTNAME; 2048-bit key, 365 days; key 600, crt 644.
##   Skipped when both key and crt already exist. Used only by
##   mkrootfs_fedora_install_codepad.
##

function create_codepad_certificate() { #rootfs

    local rootfs
    rootfs="$1"

    ## Create a certificate
    ## FIXME(v4): the ssl_* variables below leak into the global shell
    ## (not local) — the certificates module conditionally reuses a
    ## pre-set ssl_password (domaincertlib.sh), so they stay global here.
    ssl_password="no_password"
    ssl_days=365
    ssl_key="$rootfs"/var/codepad/localhost.key
    ssl_csr="$rootfs"/var/codepad/localhost.csr
    ssl_org="$rootfs"/var/codepad/localhost.org.pem
    ssl_crt="$rootfs"/var/codepad/localhost.crt
    ssl_config="$rootfs"/var/codepad/localhost-cert-config.txt

    if [[ ! -f "$ssl_key" ]] || [[ ! -f "$ssl_crt" ]]
    then

## FIXME(v4): appending — after a partial previous run (key present, crt
## missing) the guard re-enters and the config accumulates duplicate sections.
cat  <<EOF>> "$ssl_config"

        RANDFILE               = /tmp/ssl_random

        [ req ]
        prompt                 = no
        string_mask            = utf8only
        default_bits           = 2048
        default_keyfile        = keyfile.pem
        distinguished_name     = req_distinguished_name

        req_extensions         = v3_req

        output_password        = no_password

        [ req_distinguished_name ]
        CN                     = $HOSTNAME
        emailAddress           = webmaster@$HOSTNAME

        [ v3_req ]
        basicConstraints = critical,CA:FALSE
        keyUsage = keyEncipherment, dataEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names
        [alt_names]
        DNS.1 = $HOSTNAME
        DNS.2 = *.$HOSTNAME

EOF

        ## Generate a Private Key
        openssl genrsa -des3 -passout "pass:$ssl_password" -out "$ssl_key" 2048

        ## Generate a CSR (Certificate Signing Request)
        openssl req -new -passin "pass:$ssl_password" -passout "pass:$ssl_password" -key "$ssl_key" -out "$ssl_csr" -days "$ssl_days" -config "$ssl_config"

        ## Remove Passphrase from Key
        cp "$ssl_key" "$ssl_org"
        openssl rsa -passin "pass:$ssl_password" -in "$ssl_org" -out "$ssl_key"

        ## Self-Sign Certificate
        openssl x509 -req -days "$ssl_days" -passin "pass:$ssl_password" -extensions v3_req -in "$ssl_csr" -signkey "$ssl_key" -out "$ssl_crt"

        chmod 600 "$ssl_key"
        chmod 644 "$ssl_crt"

        msg "Created certificate $ssl_key $ssl_crt"

    fi

}
