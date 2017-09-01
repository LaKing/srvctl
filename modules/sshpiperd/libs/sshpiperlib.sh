#!/bin/bash

function mount_sshpiper() {
    
    if mount | grep "on /var/sshpiper type fuse" > /dev/null
    then
        debug "/var/sshpiper is mounted"
    else
        #run bindfs -r -p +X --map=root/sshpiper "/var/srvctl3/gluster/srvctl-data/users" /var/sshpiper
        run bindfs -r -p +X --map=root/sshpiper "/var/srvctl3/datastore/users" /var/sshpiper
    fi
    
}
