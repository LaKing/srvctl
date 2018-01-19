#!/bin/bash

function ca_sync() {
    if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
    then
        msg "This is the CA server"
    else
        if [ "$(ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" hostname 2> /dev/null)" == "$SC_ROOTCA_HOST" ]
        then
            run "rsync -aze ssh $SC_ROOTCA_HOST:/etc/srvctl/CA /etc/srvctl"
        else
            err "The CA server could not be reached!"
        fi
    fi
    
}
