#!/bin/bash

function init_openvpn_create_ca_certificates() { #net #sid
    local NET SID
    ## usernet / hostnet / whatevernet
    NET="$1"
    ## root / server / user / whatever
    SID="$2"
    
    msg "init_openvpn_create_ca_certificates $NET $SID"
    
    create_ca_certificate server "$NET" "$SID"
    create_ca_certificate client "$NET" "$SID"
}

function init_openvpn_rootca_certificates() { #net
    local NET SID
    ## usernet / hostnet / whatevernet
    NET="$1"
    
    ## then get the certificates
    if [[ "$SC_ROOTCA_HOST" != "$HOSTNAME" ]]
    then
        return
    fi
    
    msg "init_openvpn_rootca_certificates $NET"
    
    root_CA_init "$NET"
    
    create_ca_certificate client "$NET" root
    
    for S in $(get cluster host_list)
    do
        init_openvpn_create_ca_certificates "$NET" "$S"
    done
    
    cat /etc/srvctl/CA/ca/"$NET".crt.pem > /etc/openvpn/"$NET"-ca.crt.pem
    
    cat /etc/srvctl/CA/"$NET"/server-"$HOSTNAME".key.pem > /etc/openvpn/"$NET"-server.key.pem
    cat /etc/srvctl/CA/"$NET"/server-"$HOSTNAME".crt.pem > /etc/openvpn/"$NET"-server.crt.pem
    
    cat /etc/srvctl/CA/"$NET"/client-"$HOSTNAME".key.pem > /etc/openvpn/"$NET"-client.key.pem
    cat /etc/srvctl/CA/"$NET"/client-"$HOSTNAME".crt.pem > /etc/openvpn/"$NET"-client.crt.pem
    
}

function grab_openvpn_rootca_certificates() { #net
    
    local NET SID
    ## usernet / hostnet / whatevernet
    NET="$1"
    
    if [ "$(ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" hostname 2> /dev/null)" == "$SC_ROOTCA_HOST" ]
    then
        
        msg "regenerate openvpn certificate config for $NET - CA is $SC_ROOTCA_HOST"
        local options
        
        # shellcheck disable=SC2029
        ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" "/bin/srvctl exec-function init_openvpn_create_ca_certificates $NET $HOSTNAME"
        
        options="--no-R --no-implied-dirs -avze ssh"
        
        if [ ! -f /etc/openvpn/"$NET"-ca.crt.pem ]
        then
            msg "Grabbing CA certificates from $SC_ROOTCA_HOST for openvpn $NET"
            run rsync "$options" "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/ca/$NET.crt.pem" /etc/openvpn/"$NET"-ca.crt.pem
        fi
        
        if [ ! -f /etc/openvpn/"$NET"-server.crt.pem ] || [ ! -f /etc/openvpn/"$NET"-server.key.pem ]
        then
            msg "Grabbing usernet $HOSTNAME server certificate from $SC_ROOTCA_HOST for openvpn $NET"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/$NET/server-$HOSTNAME.crt.pem" /etc/openvpn/"$NET"-server.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/$NET/server-$HOSTNAME.key.pem" /etc/openvpn/"$NET"-server.key.pem
        fi
        
        if [ ! -f /etc/openvpn/"$NET"-client.crt.pem ] || [ ! -f /etc/openvpn/"$NET"-client.key.pem ]
        then
            msg "Grabbing usernet $HOSTNAME client certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/$NET/client-$HOSTNAME.crt.pem" /etc/openvpn/"$NET"-client.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/$NET/client-$HOSTNAME.key.pem" /etc/openvpn/"$NET"-client.key.pem
        fi
        
    else
        err "CA $SC_ROOTCA_HOST connection failed!"
    fi
    
}
