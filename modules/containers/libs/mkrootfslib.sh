#!/bin/bash

#[[ $SRVCTL ]] || exit
#[[ $SC_ROOTFS_DIR ]] || exit

function mkrootfs_root_ssh { ## rootfs
    
    local rootfs
    rootfs="$1"
    
    if [[ ! -d "$rootfs/root" ]]
    then
        err "No rootfs for setup_rootfs_ssh "
    else
        ## make root's key access
        mkdir -p "$rootfs/root"
        mkdir -m 600 "$rootfs/root/.ssh"
        cat /root/.ssh/id_ecdsa.pub > "$rootfs/root/.ssh/authorized_keys"
        cat /root/.ssh/authorized_keys >> "$rootfs/root/.ssh/authorized_keys"
        chmod 600 "$rootfs/root/.ssh/authorized_keys"
        
        ## disable password authentication on ssh
        #sed -i.bak "s/PasswordAuthentication yes/PasswordAuthentication no/g" "$rootfs/etc/ssh/sshd_config"
    fi
    
    if [[ -d "$rootfs/etc/ssh" ]]
    then
        cat "$SC_INSTALL_DIR/modules/ssh/sshd_config" > "$rootfs/etc/ssh/sshd_config"
    fi
}

function mkrootfs_adduser { ## name ## username
    
    local rootfs_name rootfs_base rootfs_user
    
    rootfs_name="$1"
    rootfs_base="$SC_ROOTFS_DIR/$rootfs_name"
    
    rootfs_user="$2"
    
    msg "Add user $rootfs_user to $rootfs_name"
    chroot "$rootfs_base" groupadd -r -g 1000 "$rootfs_user"
    chroot "$rootfs_base" useradd -r -u 1000 -g 1000 -s /bin/bash -d "/home/$rootfs_user" "$rootfs_user"
    
    mkdir -p "$rootfs_base/home/$rootfs_user/.ssh"
    
    ## bash files will be based on root's bash files
    cat "$rootfs_base"/root/.bash_profile > "$rootfs_base/home/$rootfs_user/.bash_profile"
    cat "$rootfs_base"/root/.bash_logout > "$rootfs_base/home/$rootfs_user/.bash_logout"
    cat "$rootfs_base"/root/.bashrc > "$rootfs_base/home/$rootfs_user/.bashrc"
    
    ## roots is authorized for login
    cat /root/.ssh/authorized_keys > "$rootfs_base/home/$rootfs_user/.ssh/authorized_keys"
    chmod 700  "$rootfs_base/home/$rootfs_user/.ssh"
    
    chroot "$rootfs_base" chown -R "$rootfs_user":"$rootfs_user" /home/"$rootfs_user"
    chroot "$rootfs_base" chmod u+rwX /home/"$rootfs_user"
    
}

