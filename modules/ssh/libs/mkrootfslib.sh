#!/bin/bash

## this is for container creation /update
function mkrootfs_sshd_config { ## rootfs
    
    local rootfs
    rootfs="$1"
    
    if [[ ! -f "$rootfs/etc/ssh/sshd_config" ]]
    then
        err "No ssh setup present."
        return
    fi
    
    msg "mkrootfs_ssh_config $rootfs"
    cat "$SC_INSTALL_DIR/modules/ssh/sshd_config" > "$rootfs/etc/ssh/sshd_config"
    
}
