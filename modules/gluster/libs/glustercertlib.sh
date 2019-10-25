#!/bin/bash

## NOT USED ##
return

function init_gluster_rootca_certificates() {
    
    ## then get the certificates
    if [[ "$SC_ROOTCA_HOST" != "$HOSTNAME" ]]
    then
        return
    fi
    
    root_CA_init glusternet
    
    create_ca_certificate client glusternet root
    create_ca_certificate server glusternet "$HOSTNAME"
    create_ca_certificate client glusternet "$HOSTNAME"
    
    cat /etc/srvctl/CA/ca/glusternet.crt.pem > /etc/glusterfs/glusternet-ca.crt.pem
    cat /etc/srvctl/CA/ca/hostnet.crt.pem > /etc/glusterfs/hostnet-ca.crt.pem
    
    cat /etc/srvctl/CA/glusternet/server-"$HOSTNAME".key.pem > /etc/glusterfs/glusternet-server.key.pem
    cat /etc/srvctl/CA/glusternet/server-"$HOSTNAME".crt.pem > /etc/glusterfs/glusternet-server.crt.pem
    
    cat /etc/srvctl/CA/glusternet/client-"$HOSTNAME".key.pem > /etc/glusterfs/glusternet-client.key.pem
    cat /etc/srvctl/CA/glusternet/client-"$HOSTNAME".crt.pem > /etc/glusterfs/glusternet-client.crt.pem
    
    for S in $(get cluster host_list)
    do
        ## glusterfs client certificate
        create_ca_certificate server glusternet "$S"
        create_ca_certificate client glusternet "$S"
    done
    
}

function grab_gluster_rootca_certificates() {
    
    if [ "$(ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" hostname 2> /dev/null)" == "$SC_ROOTCA_HOST" ]
    then
        
        msg "regenerate glusterfs certificate config - CA is $SC_ROOTCA_HOST"
        local H options
        H="$HOSTNAME"
        
        options="--no-R --no-implied-dirs -avze ssh"
        
        if [ ! -f /etc/glusterfs/glusternet-ca.crt.pem ]
        then
            msg "Grabbing CA certificates from $SC_ROOTCA_HOST for glusterfs"
            run rsync "$options" "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/ca/glusternet.crt.pem" /etc/glusterfs/glusternet-ca.crt.pem
        fi
        
        if [ ! -f /etc/glusterfs/glusternet-server.crt.pem ] || [ ! -f /etc/glusterfs/glusternet-server.key.pem ]
        then
            msg "Grabbing glusternet $HOSTNAME server certificate from $SC_ROOTCA_HOST for glusterfs"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/glusternet/server-$H.crt.pem" /etc/glusterfs/glusternet-server.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/glusternet/server-$H.key.pem" /etc/glusterfs/glusternet-server.key.pem
        fi
        
        if [ ! -f /etc/glusterfs/glusternet-client.crt.pem ] || [ ! -f /etc/glusterfs/glusternet-client.key.pem ]
        then
            msg "Grabbing glusternet $HOSTNAME client certificate from $SC_ROOTCA_HOST for glusterfs"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/glusternet/client-$H.crt.pem" /etc/glusterfs/glusternet-client.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/glusternet/client-$H.key.pem" /etc/glusterfs/glusternet-client.key.pem
        fi
        
    else
        err "CA $SC_ROOTCA_HOST connection failed!"
    fi
    
}
