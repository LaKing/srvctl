#!/bin/bash

## https://github.com/coolaj86/nodejs-ssl-trusted-peer-example/blob/master/make-root-ca-and-certificates.sh


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
    
    if [[ ! -f "$SC_ROOTCA_DIR/ca/$_net.srl" ]]
    then
        echo 02 > "$SC_ROOTCA_DIR/ca/$_net.srl"
        
        run openssl x509 -noout -text -in "$SC_ROOTCA_DIR/ca/$_net.crt.pem"
    fi
    
    
}


function root_CA_init {
    
    if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
    then
        
        msg "root CA init $1"
        
        # make directories to work from
        mkdir -p "$SC_ROOTCA_DIR/$1"
        
        mkdir -p "$SC_ROOTCA_DIR/ca"
        mkdir -p "$SC_ROOTCA_DIR/tmp"
        
        chmod -R 600 "$SC_ROOTCA_DIR"
        
        root_CA_create "$1"
        
        rm -fr /etc/srvctl/CA/tmp/*
    fi
}


function create_ca_certificate { ## type net name
    
    if [[ "$SC_ROOTCA_HOST" != "$HOSTNAME" ]]
    then
        return
    fi
    
    local _e _net _u _ext _file
    
    ## network: server / client
    _e="$1"
    ## usernet / hostnet
    _net="$2"
    ## user / root / host -name
    _u="$3"
    
    _ext=''
    
    ## check for correct arguments
    if [[ "$_e" == server ]] || [[ "$_e" == client ]]
    then
        local _file="$_e-$_u"
    else
        err "create_ca_certificate error client/server not specified!"
        return
    fi
    
    if [[ "$_e" == server ]]
    then
        _ext="-extfile $SC_INSTALL_DIR/modules/certificates/openssl-server-ext.cnf -extensions server"
    fi
    
    msg "CA-lib create_ca_certificate $_e $_net $_u"
    
    ## Check if certificate is invalid or expired and remove if so
    if  [[ -f "$SC_ROOTCA_DIR/$_net/$_file.key.pem" ]] && [[ -f "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" ]]
    then
        
        if [[ "$(openssl x509 -noout -modulus -in "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" | openssl md5)" == "$(openssl rsa -noout -modulus -in "$SC_ROOTCA_DIR/$_net/$_file.key.pem" | openssl md5)" ]]
        then
            if openssl x509 -checkend 86400 -noout -in "$SC_ROOTCA_DIR/$_net/$_file.crt.pem"
            then
                echo "$_net certificate for $_u is OK" > /dev/null
            else
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
        #echo "openssl genrsa -out $SC_ROOTCA_DIR/$_net/$_file.key.pem 4096"
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
        
        run openssl x509 "$_ext" \
        -req -in "$SC_ROOTCA_DIR/tmp/$_file.csr.pem" \
        -CA "$SC_ROOTCA_DIR/ca/$_net.crt.pem" \
        -CAkey "$SC_ROOTCA_DIR/ca/$_net.key.pem" \
        -CAserial "$SC_ROOTCA_DIR/ca/$_net.srl" \
        -out "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" \
        -days 1095
    fi
    
    
    if [[ $_e == client ]] && [[ $_net == usernet ]]
    then
        
        if [[ ! -f "$SC_ROOTCA_DIR/$_net/$_file.p12" ]]
        then
            local _passphrase
            ##_passphrase="$(cat "/var/srvctl-users/$_u/.password")"
            _passphrase="$(new_password)"
            if [[ ! -z "$_passphrase" ]]
            then
                
                ntc "create $_file p12 ($_passphrase)"
                
                run openssl pkcs12 -export \
                -passout pass:"$_passphrase" \
                -in "$SC_ROOTCA_DIR/$_net/$_file.crt.pem" \
                -inkey "$SC_ROOTCA_DIR/$_net/$_file.key.pem" \
                -out "$SC_ROOTCA_DIR/$_net/$_file.p12"
                
                echo "$_passphrase ($NOW)" > "$SC_ROOTCA_DIR/$_net/$_file.pass"
                cat "$SC_ROOTCA_DIR/$_net/$_file.pass"
                
            fi
            
            #if [[ ! -f "/home/$_u/$SC_COMPANY_DOMAIN-$_file.p12" ]]
            #then
            #    cat "$SC_ROOTCA_DIR/$_net/$_file.p12" > "/home/$_u/$SC_COMPANY_DOMAIN-$_file.p12"
            #    chown "$_u:$_u" "/home/$_u/$SC_COMPANY_DOMAIN-$_file.p12"
            #    chmod 400 "/home/$_u/$SC_COMPANY_DOMAIN-$_file.p12"
            #fi
            
            if [[ -f "$SC_ROOTCA_DIR/$_net/$_file.p12" ]]
            then
                mkdir -p $SC_DATASTORE_DIR/users
                cat "$SC_ROOTCA_DIR/$_net/$_file.p12" > "$SC_DATASTORE_DIR/users/$_u/$_u@$SC_COMPANY_DOMAIN.p12"
                cat "$SC_ROOTCA_DIR/$_net/$_file.pass" > "$SC_DATASTORE_DIR/users/$_u/$_u@$SC_COMPANY_DOMAIN.pass"
            fi
            
        fi
    fi
    # verify server extension
    #openssl x509 -noout -text -in $SC_ROOTCA_DIR/$_net/$_file.crt.pem
    #openssl x509 -noout -in /etc/srvctl/CA/hostnet/server-sc.d250.hu.crt.pem -purpose
    #sleep 2
    
    #else
    #    msg ".. this is not the CA"
    
}

