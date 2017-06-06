#!/bin/bash

## this is for container creation
function mkrootfs_root_ssh_config { ## rootfs
    
    local rootfs
    rootfs="$1"
    
    if [[ ! -d "$rootfs/root" ]]
    then
        err "No rootfs for setup_rootfs_ssh "
    else
        ## make root's key access
        mkdir -p -m 600 "$rootfs/root/.ssh"
        cat /etc/srvctl/authorized_keys > "$rootfs/root/.ssh/authorized_keys"
        cat "$SC_DATASTORE_DIR/users/$SC_USER/authorized_keys" >> "$rootfs/root/.ssh/authorized_keys"
        
        chmod 600 "$rootfs/root/.ssh/authorized_keys"
        
        ## disable password authentication on ssh
        sed -i.bak "s/PasswordAuthentication yes/PasswordAuthentication no/g" "$rootfs/etc/ssh/sshd_config"
    fi
}
