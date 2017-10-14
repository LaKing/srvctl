#!/bin/bash

function init_openvpn_create_ca_certificates() {
    local S
    S="$1"
    msg "init_openvpn_create_ca_certificates $S"
    
    create_ca_certificate server usernet "$S"
    create_ca_certificate server hostnet "$S"
    
    create_ca_certificate client usernet "$S"
    create_ca_certificate client hostnet "$S"
}

function init_openvpn_rootca_certificates() {
    
    ## then get the certificates
    if [[ "$SC_ROOTCA_HOST" != "$HOSTNAME" ]]
    then
        return
    fi
    
    msg "init_openvpn_rootca_certificates"
    
    root_CA_init hostnet
    root_CA_init usernet
    
    create_ca_certificate client usernet root
    create_ca_certificate client hostnet root
    
    for S in $(cfg cluster host_list)
    do
        init_openvpn_create_ca_certificates "$S"
    done
    
    cat /etc/srvctl/CA/ca/usernet.crt.pem > /etc/openvpn/usernet-ca.crt.pem
    cat /etc/srvctl/CA/ca/hostnet.crt.pem > /etc/openvpn/hostnet-ca.crt.pem
    
    cat /etc/srvctl/CA/usernet/server-"$HOSTNAME".key.pem > /etc/openvpn/usernet-server.key.pem
    cat /etc/srvctl/CA/usernet/server-"$HOSTNAME".crt.pem > /etc/openvpn/usernet-server.crt.pem
    
    cat /etc/srvctl/CA/hostnet/server-"$HOSTNAME".key.pem > /etc/openvpn/hostnet-server.key.pem
    cat /etc/srvctl/CA/hostnet/server-"$HOSTNAME".crt.pem > /etc/openvpn/hostnet-server.crt.pem
    
    cat /etc/srvctl/CA/usernet/client-"$HOSTNAME".key.pem > /etc/openvpn/usernet-client.key.pem
    cat /etc/srvctl/CA/usernet/client-"$HOSTNAME".crt.pem > /etc/openvpn/usernet-client.crt.pem
    
    cat /etc/srvctl/CA/hostnet/client-"$HOSTNAME".key.pem > /etc/openvpn/hostnet-client.key.pem
    cat /etc/srvctl/CA/hostnet/client-"$HOSTNAME".crt.pem > /etc/openvpn/hostnet-client.crt.pem
    
    
    
}



function grab_openvpn_rootca_certificates() {
    
    if [ "$(ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" hostname 2> /dev/null)" == "$SC_ROOTCA_HOST" ]
    then
        
        msg "regenerate openvpn certificate config - CA is $SC_ROOTCA_HOST"
        local options
        
        # shellcheck disable=SC2029
        ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" "/bin/srvctl exec-function init_openvpn_create_ca_certificates $HOSTNAME"
        
        options="--no-R --no-implied-dirs -avze ssh"
        
        if [ ! -f /etc/openvpn/usernet-ca.crt.pem ] || [ ! -f /etc/openvpn/hostnet-ca.crt.pem ]
        then
            msg "Grabbing CA certificates from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options" "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/ca/usernet.crt.pem" /etc/openvpn/usernet-ca.crt.pem
            run rsync "$options" "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/ca/hostnet.crt.pem" /etc/openvpn/hostnet-ca.crt.pem
        fi
        
        if [ ! -f /etc/openvpn/usernet-server.crt.pem ] || [ ! -f /etc/openvpn/usernet-server.key.pem ]
        then
            msg "Grabbing usernet $HOSTNAME server certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/usernet/server-$HOSTNAME.crt.pem" /etc/openvpn/usernet-server.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/usernet/server-$HOSTNAME.key.pem" /etc/openvpn/usernet-server.key.pem
        fi
        
        if [ ! -f /etc/openvpn/hostnet-server.crt.pem ] || [ ! -f /etc/openvpn/hostnet-server.key.pem ]
        then
            msg "Grabbing hostnet $HOSTNAME server certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/hostnet/server-$HOSTNAME.crt.pem" /etc/openvpn/hostnet-server.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/hostnet/server-$HOSTNAME.key.pem" /etc/openvpn/hostnet-server.key.pem
        fi
        
        if [ ! -f /etc/openvpn/usernet-client.crt.pem ] || [ ! -f /etc/openvpn/usernet-client.key.pem ]
        then
            msg "Grabbing usernet $HOSTNAME client certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/usernet/client-$HOSTNAME.crt.pem" /etc/openvpn/usernet-client.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/usernet/client-$HOSTNAME.key.pem" /etc/openvpn/usernet-client.key.pem
        fi
        
        if [ ! -f /etc/openvpn/hostnet-client.crt.pem ] || [ ! -f /etc/openvpn/hostnet-client.key.pem ]
        then
            msg "Grabbing hostnet $HOSTNAME client certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/hostnet/client-$HOSTNAME.crt.pem" /etc/openvpn/hostnet-client.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/hostnet/client-$HOSTNAME.key.pem" /etc/openvpn/hostnet-client.key.pem
        fi
    else
        err "CA $SC_ROOTCA_HOST connection failed!"
    fi
    
}
