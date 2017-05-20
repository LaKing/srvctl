#!/bin/bash

function regenerate_pound_conf {
    ## static ve-host-certificiates with priority from etc
    ## container certificates from gluster share
    msg "Regenerate pound configs."
    mkdir -p /var/pound/cert
    mkdir -p /etc/srvctl/cert
    mkdir -p /var/srvctl3-datastore/rw/cert
    rsync -a /var/srvctl3-datastore/rw/cert /var/srvctl3-datastore/ro
    rsync -a /var/srvctl3-datastore/ro/cert /var/pound
    poundcfg
    restart_pound
}


function restart_pound {
    
    systemctl restart pound.service
    
    test=$(systemctl is-active pound.service)
    
    if [ "$test" == "active" ]
    then
        msg "restarted pound.service"
    else
        ## pound syntax check
        pound -c -f /etc/pound.cfg
        
        err "Pound restart FAILED!"
        systemctl status pound.service --no-pager
    fi
}

