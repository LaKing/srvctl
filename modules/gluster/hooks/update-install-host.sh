#!/bin/bash

##
##   modules/gluster/hooks/update-install-host.sh — gluster TLS material and
##   package install.
##
##   Fired by "run_hooks update-install-host" during "sc update-install" on a
##   host. Never runs at this commit: the module is hard-disabled at baseline
##   (see module-condition.sh) and is a deprecation candidate for v4.
##
##   On the CA host (SC_ROOTCA_HOST == HOSTNAME): initializes the "gluster"
##   CA (ca module), issues server certificates for this host and every
##   cluster host, and installs the CA cert plus own server key/cert as
##   /etc/ssl/gluster-{ca.crt,server.key,server.crt}.pem.
##   On every other host: pulls the missing /etc/ssl/gluster-*.pem files from
##   the CA host with rsync over ssh.
##   Finally generates /etc/ssl/dhparam.pem if absent and runs
##   gluster_install (libs/glusterlib.sh).
##

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

    cat /etc/srvctl/CA/ca/gluster.crt.pem > /etc/ssl/gluster-ca.crt.pem

    cat /etc/srvctl/CA/gluster/server-"$HOSTNAME".key.pem > /etc/ssl/gluster-server.key.pem
    cat /etc/srvctl/CA/gluster/server-"$HOSTNAME".crt.pem > /etc/ssl/gluster-server.crt.pem

    for S in $(get cluster host_list)
    do
        ## ssl gluster certificate
        create_ca_certificate server gluster "$S"
    done
    
else
    
    ## FIXME(v4): the reachability probe disables host-key verification (so it
    ## is MITM-able while deciding to fetch CA material), yet the rsync
    ## transfers below use default ssh settings — on a fresh host with no
    ## known_hosts entry for the CA, an unattended update-install blocks on an
    ## interactive host-key prompt.
    if [[ "$(ssh -n -o ConnectTimeout=1 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$SC_ROOTCA_HOST" hostname 2> /dev/null)" == "$SC_ROOTCA_HOST" ]]
    then

        msg "regenerate gluster certificate config - CA is $SC_ROOTCA_HOST"
        ## hooks are sourced, not functions, so "local" is unavailable here
        H="$HOSTNAME"

        ## NOTE: "$options" is passed as a single word below and relies on
        ## run() expanding $* unquoted (lablib.sh) to re-split it into rsync
        ## flags — do not quote it "properly" without changing run().
        options="--no-R --no-implied-dirs -avze ssh"

        if [[ ! -f /etc/ssl/gluster-ca.crt.pem ]]
        then
            msg "Grabbing CA certificates from $SC_ROOTCA_HOST for ssl"
            run rsync "$options" "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/ca/gluster.crt.pem" /etc/ssl/gluster-ca.crt.pem
        fi
        
        if [[ ! -f /etc/ssl/gluster-server.crt.pem ]]
        then
            msg "Grabbing gluster $HOSTNAME server certificate from $SC_ROOTCA_HOST for ssl"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/gluster/server-$H.crt.pem" /etc/ssl/gluster-server.crt.pem
        fi

        if [[ ! -f /etc/ssl/gluster-server.key.pem ]]
        then
            msg "Grabbing gluster $HOSTNAME server certificate from $SC_ROOTCA_HOST for ssl"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/gluster/server-$H.key.pem" /etc/ssl/gluster-server.key.pem
        fi
    else
        err "CA $SC_ROOTCA_HOST connection failed!"
    fi
    
fi

## generate this for the certificates
if [[ ! -f /etc/ssl/dhparam.pem ]]
then
    run openssl dhparam -out /etc/ssl/dhparam.pem 2048
fi

gluster_install
