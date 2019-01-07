#!/bin/bash

## we can run this directly with:
## sc exec-function run_module_hook gluster update-install

if [[ -z $SC_ROOTCA_HOST ]]
then
    err "SC_ROOTCA_HOST not defined. The gluster installation can not continue."
    return
fi


## then get the certificates
if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
then
    root_CA_init gluster
    
    create_ca_certificate client gluster root
    
    create_ca_certificate server gluster "$HOSTNAME"
    #create_ca_certificate client gluster "$HOSTNAME"
    
    cat /etc/srvctl/CA/ca/gluster.crt.pem > /etc/ssl/gluster-ca.crt.pem
    
    cat /etc/srvctl/CA/gluster/server-"$HOSTNAME".key.pem > /etc/ssl/gluster-server.key.pem
    cat /etc/srvctl/CA/gluster/server-"$HOSTNAME".crt.pem > /etc/ssl/gluster-server.crt.pem
    #cat /etc/srvctl/CA/gluster/client-"$HOSTNAME".key.pem > /etc/ssl/gluster-client.key.pem
    #cat /etc/srvctl/CA/gluster/client-"$HOSTNAME".crt.pem > /etc/ssl/gluster-client.crt.pem
    
    
    for S in $(cfg cluster host_list)
    do
        ## ssl gluster certificate
        create_ca_certificate server gluster "$S"
        #create_ca_certificate client gluster "$S"
    done
    
else
    
    if [ "$(ssh -n -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$SC_ROOTCA_HOST" hostname 2> /dev/null)" == "$SC_ROOTCA_HOST" ]
    then
        
        msg "regenerate gluster certificate config - CA is $SC_ROOTCA_HOST"
        #local H options
        H="$HOSTNAME"
        
        options="--no-R --no-implied-dirs -avze ssh"
        
        if [ ! -f /etc/ssl/gluster-ca.crt.pem ]
        then
            msg "Grabbing CA certificates from $SC_ROOTCA_HOST for ssl"
            run rsync "$options" "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/ca/gluster.crt.pem" /etc/ssl/gluster-ca.crt.pem
        fi
        
        if [ ! -f /etc/ssl/gluster-server.crt.pem ]
        then
            msg "Grabbing gluster $HOSTNAME server certificate from $SC_ROOTCA_HOST for ssl"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/gluster/server-$H.crt.pem" /etc/ssl/gluster-server.crt.pem
        fi
        
        if [ ! -f /etc/ssl/gluster-server.key.pem ]
        then
            msg "Grabbing gluster $HOSTNAME server certificate from $SC_ROOTCA_HOST for ssl"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/gluster/server-$H.key.pem" /etc/ssl/gluster-server.key.pem
        fi
        
        #if [ ! -f /etc/ssl/gluster-client.crt.pem ] || [ ! -f /etc/ssl/gluster-client.key.pem ]
        #then
        #    msg "Grabbing gluster $HOSTNAME client certificate from $SC_ROOTCA_HOST for ssl"
        #    run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/gluster/client-$H.crt.pem" /etc/ssl/gluster-client.crt.pem
        #fi
        
        #if [ ! -f /etc/ssl/gluster-client.crt.pem ] || [ ! -f /etc/ssl/gluster-client.key.pem ]
        #then
        #    msg "Grabbing gluster $HOSTNAME client certificate from $SC_ROOTCA_HOST for ssl"
        #    run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/gluster/client-$H.crt.pem" /etc/ssl/gluster-client.crt.pem
        #fi
    else
        err "CA $SC_ROOTCA_HOST connection failed!"
    fi
    
fi

## generate this for the certificates
if [ ! -f /etc/ssl/dhparam.pem ]
then
    run openssl dhparam -out /etc/ssl/dhparam.pem 2048
fi

gluster_install


