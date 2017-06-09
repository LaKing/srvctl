#!/bin/bash

function regenerate_pound_conf {
    ## static ve-host-certificiates with priority from etc
    ## container certificates from gluster share
    msg "Regenerate pound configs."
    mkdir -p /var/pound/cert
    mkdir -p /etc/srvctl/cert
    mkdir -p /var/srvctl3/datastore/rw/cert
    rsync -a /var/srvctl3/datastore/rw/cert /var/srvctl3/datastore/ro
    rsync -a /var/srvctl3/datastore/ro/cert /var/pound
    poundcfg
    restart_pound
}

