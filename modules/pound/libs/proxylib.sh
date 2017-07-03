#!/bin/bash

function regenerate_pound_conf {
    ## static ve-host-certificiates with priority from etc
    ## container certificates from gluster share
    
    run mkdir -p "$SC_DATASTORE_DIR/cert"
    msg "Regenerate pound configs."
    mkdir -p /var/pound/cert
    mkdir -p /etc/srvctl/cert
    run rsync -a "$SC_DATASTORE_RO_DIR/cert" /var/pound
    poundcfg
    restart_pound
    
}

