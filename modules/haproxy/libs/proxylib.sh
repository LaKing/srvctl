#!/bin/bash

function regenerate_haproxy_conf {
    ## static ve-host-certificiates with priority from etc
    ## container certificates from gluster share
    
    mkdir -p "$SC_DATASTORE_DIR/cert"
    mkdir -p "$SC_DATASTORE_DIR/pki-validation"
    
    msg "Regenerate haproxy configs."
    ## the haproxy certificates will be loaded from /var/haproxy
    mkdir -p /var/haproxy
    ## we may have server-wide wildcard certificates
    mkdir -p /etc/srvctl/cert
    
    cp -u /var/srvctl3/datastore/cert/* /var/haproxy/
    cp -u /etc/srvctl/cert/*/*.pem /var/haproxy/
    rm -fr /var/haproxy/ca-bundle.pem
    #run rsync -a "$SC_DATASTORE_RO_DIR/cert" /var/haproxy
    
    haproxycfg
    #restart_haproxy
    ## better reload
    reload_haproxy
}

