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
    
    if false
    then
        ## disable password authentication on ssh
        sed -i.bak "s/PasswordAuthentication yes/PasswordAuthentication no/g" "$rootfs/etc/ssh/sshd_config"
        
        local sedstr
        sed -i.bak "s|#AuthorizedKeysCommandUser nobody|AuthorizedKeysCommandUser root|g" "$rootfs/etc/ssh/sshd_config"
        sedstr="AuthorizedKeysCommand /usr/bin/cat $SC_DATASTORE_RW_DIR/users/%u/authorized_keys /etc/srvctl/authorized_keys"
        sed -i.bak "s|#AuthorizedKeysCommand none|$sedstr## |g" /etc/ssh/sshd_config
    fi
    
    msg "mkrootfs_ssh_config $rootfs"
    cat "$SC_INSTALL_DIR/modules/ssh/sshd_config" > "$rootfs/etc/ssh/sshd_config"
    
}
