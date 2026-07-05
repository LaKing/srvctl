#!/bin/bash

##
##   modules/ca/libs/calib.sh — private root-CA and certificate issuance.
##
##   Cross-module API (consumed by certificates, gluster and openvpn; also
##   invoked remotely by name via "srvctl exec-function" chains):
##     root_CA_init NET     - create the CA directory layout and root CA
##     root_CA_create NET   - root key/cert/serial for NET, only if missing
##     create_ca_certificate {server|client} NET NAME
##                          - issue or renew a 4096-bit RSA leaf cert signed
##                            by NET's root CA; usernet client certs are
##                            additionally exported as a passwordless .p12
##   Issuance happens only on the CA host (SC_ROOTCA_HOST == HOSTNAME);
##   everywhere else these functions silently no-op — consumer hooks rely
##   on that being non-fatal. State lives under SC_ROOTCA_DIR (default
##   /etc/srvctl/CA): ca/NET.{key,crt}.pem, ca/NET.srl,
##   NET/{server|client}-NAME.{key,crt}.pem, usernet/client-NAME.p12,
##   tmp/*.csr.pem.
##
##   Original recipe:
##   https://github.com/coolaj86/nodejs-ssl-trusted-peer-example/blob/master/make-root-ca-and-certificates.sh
##


## create the root CA material for network $1 under $SC_ROOTCA_DIR/ca.
## Each artifact is created only if its file is missing.
function root_CA_create {

    local _net=$1

    if [[ ! -f "$SC_ROOTCA_DIR/ca/$_net.key.pem" ]]
    then
        # Create own Root Certificate Authority
        msg "create $_net ca-key"

        run openssl genrsa \
        -out "$SC_ROOTCA_DIR/ca/$_net.key.pem" \
        4096

        chmod 600 "$SC_ROOTCA_DIR/ca/$_net.key.pem"
    fi

    ## FIXME(v4): no expiry check on the root CA cert (unlike leaf certs
    ## below) — after the 3652 days issuance continues against an expired CA
    ## with no self-healing.
    if [[ ! -f "$SC_ROOTCA_DIR/ca/$_net.crt.pem" ]]
    then
        msg "create $_net ca-cert"
        run openssl req \
        -x509 \
        -new \
        -nodes \
        -key "$SC_ROOTCA_DIR/ca/$_net.key.pem" \
        -days 3652 \
        -out "$SC_ROOTCA_DIR/ca/$_net.crt.pem" \
        -subj "$SC_ROOTCA_SUBJ/CN=$SC_COMPANY-$_net-ca"
    fi

    ## seed the serial file — leaf signing uses -CAserial, not
    ## -CAcreateserial — and print the fresh CA cert once
    if [[ ! -f "$SC_ROOTCA_DIR/ca/$_net.srl" ]]
    then
        echo 02 > "$SC_ROOTCA_DIR/ca/$_net.srl"

        run openssl x509 -noout -text -in "$SC_ROOTCA_DIR/ca/$_net.crt.pem"
    fi


}


## on the CA host only: create the directory layout for network $1 and its
## root CA, then clean leftover CSRs. No-op on every other host.
## FIXME(v4): $1 is not validated — certificates/hooks/update-install-host.sh
## calls this with no argument, producing junk hidden CA material
## ($SC_ROOTCA_DIR/ca/.key.pem, .crt.pem with CN "$SC_COMPANY--ca", .srl).
function root_CA_init {

    if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
    then

        msg "root CA init $1"

        # make directories to work from
        mkdir -p "$SC_ROOTCA_DIR/$1"

        mkdir -p "$SC_ROOTCA_DIR/ca"
        mkdir -p "$SC_ROOTCA_DIR/tmp"

        ## FIXME(v4): chmod -R 600 strips the execute bit from every directory
        ## in the CA tree (root traverses only via DAC override), while files
        ## created afterwards (.crt.pem, .csr.pem, .srl, .p12 — the last holds
        ## a private key) get default-umask 644.
        chmod -R 600 "$SC_ROOTCA_DIR"

        root_CA_create "$1"

        ## FIXME(v4): hardcodes /etc/srvctl/CA instead of $SC_ROOTCA_DIR — with
        ## a customized SC_ROOTCA_DIR the CSR temp files are never removed.
        rm -fr /etc/srvctl/CA/tmp/*
    fi
}


## issue (or renew, if expired/invalid) a leaf certificate signed by the
## $2 network's root CA. Silent no-op off the CA host.
function create_ca_certificate { ## type net name

    if [[ "$SC_ROOTCA_HOST" != "$HOSTNAME" ]]
    then
        return
    fi

    local _e _net _u _ext _file

    ## role: server / client
    _e="$1"
    ## network: usernet / hostnet / gluster / ...
    _net="$2"
    ## subject CN: user / root / host -name
    _u="$3"

    _ext=''

    ## check for correct arguments
    if [[ "$_e" == server ]] || [[ "$_e" == client ]]
    then
        _file="$_e-$_u"
    else
        err "create_ca_certificate error client/server not specified!"
        return
    fi

    ## server certs get the x509 v3 server extensions; note the multi-flag
    ## string is passed to run as ONE argument below.
    ## FIXME(v4): depends on the certificates module's tree — the
    ## byte-identical modules/ca/openssl-server-ext.cnf is never used, and if
    ## the certificates copy moves, server cert issuance silently fails (run
    ## does not abort on openssl errors).
    if [[ "$_e" == server ]]
    then
        _ext="-extfile $SC_INSTALL_DIR/modules/certificates/openssl-server-ext.cnf -extensions server"
    fi

    msg "CA-lib create_ca_certificate $_e $_net $_u"

    ## Check if certificate is invalid or expired and remove if so
    if  [[ -f "$SC_ROOTCA_DIR/$_net/$_file.key.pem" ]] && [[ -f "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" ]]
    then
        ## cert and key must share the same RSA modulus, and the cert must
        ## remain valid for at least one more day (-checkend 86400)
        if [[ "$(openssl x509 -noout -modulus -in "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" | openssl md5)" == "$(openssl rsa -noout -modulus -in "$SC_ROOTCA_DIR/$_net/$_file.key.pem" | openssl md5)" ]]
        then
            if ! openssl x509 -checkend 86400 -noout -in "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" > /dev/null
            then
                err "$_net certificate for $_u EXPIRED"
                rm -fr "$SC_ROOTCA_DIR/$_net/$_file.crt.pem"
                rm -fr "$SC_ROOTCA_DIR/$_net/$_file.key.pem"
            fi
        else
            err "$_net certificate for $_u INVALID"
            rm -fr "$SC_ROOTCA_DIR/$_net/$_file.crt.pem"
            rm -fr "$SC_ROOTCA_DIR/$_net/$_file.key.pem"
        fi

    fi

    ## create if dont exists
    if [[ ! -f "$SC_ROOTCA_DIR/$_net/$_file.key.pem" ]] || [[ ! -f "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" ]]
    then
        msg "create $_net $_file key"
        run openssl genrsa \
        -out "$SC_ROOTCA_DIR/$_net/$_file.key.pem" \
        4096

        chmod 600 "$SC_ROOTCA_DIR/$_net/$_file.key.pem"

        msg "create $_net $_u csr"
        # Create a trusted client cert

        run openssl req -new \
        -key "$SC_ROOTCA_DIR/$_net/$_file.key.pem" \
        -out "$SC_ROOTCA_DIR/tmp/$_file.csr.pem" \
        -subj "$SC_ROOTCA_SUBJ/CN=$_u"

        msg "create $_net $_file cert"

        # Sign the request from Trusted Client with your Root CA
        # we wont use CAcreateserial

        ## "$_ext" is a multi-flag string (or empty for client certs); this
        ## only works because run expands its arguments unquoted via $*, which
        ## word-splits the flags and makes the empty argument vanish.
        ## FIXME(v4): a correct-quoting rewrite of run would break this call
        ## (openssl would receive '' as an unknown option).
        run openssl x509 "$_ext" \
        -req -in "$SC_ROOTCA_DIR/tmp/$_file.csr.pem" \
        -CA "$SC_ROOTCA_DIR/ca/$_net.crt.pem" \
        -CAkey "$SC_ROOTCA_DIR/ca/$_net.key.pem" \
        -CAserial "$SC_ROOTCA_DIR/ca/$_net.srl" \
        -out "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" \
        -days 1095
    fi

    ## usernet client certs are additionally bundled as a pkcs12 for browser/
    ## VPN import, deliberately with an empty passphrase (for now).
    if [[ $_e == client ]] && [[ $_net == usernet ]]
    then
        ## FIXME(v4): stale bundle — the .p12 is only created when missing, so
        ## after an expired/invalid cert+key pair is re-issued above, the old
        ## .p12 with the dead key survives forever; regenerate it whenever the
        ## cert is re-issued.
        if [[ ! -f "$SC_ROOTCA_DIR/$_net/$_file.p12" ]]
        then
            ntc "create $_file p12"

            run openssl pkcs12 -export \
            -in "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" \
            -inkey "$SC_ROOTCA_DIR/$_net/$_file.key.pem" \
            -out "$SC_ROOTCA_DIR/$_net/$_file.p12" \
            -passout pass:

        fi
    fi

}
