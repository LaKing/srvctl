#!/bin/bash

function regenerate_haproxy_conf {
    ## static ve-host-certificiates with priority from etc
    ## container certificates from gluster share
    
    run mkdir -p "$SC_DATASTORE_DIR/cert"
    msg "Regenerate haproxy configs."
    mkdir -p /var/haproxy
    mkdir -p /etc/srvctl/cert
    
    cp -u /var/srvctl3/datastore/cert/* /var/haproxy/
    #run rsync -a "$SC_DATASTORE_RO_DIR/cert" /var/haproxy
    
    haproxycfg
    restart_haproxy
    
}

