#!/bin/bash

function mkrootfs_fedora_base { ## N name
    
    ## this is my own version for rootfs creation
    local ROOTFS_NAME SRVCTL_PKG_LIST INSTALL_ROOT
    local ROOTFS_NAME=$1
    local SRVCTL_PKG_LIST="$2"
    local INSTALL_ROOT=$ROOTFS_DIR/$ROOTFS_NAME
    
    if [[ -d $INSTALL_ROOT/etc ]]
    then
        msg "$ROOTFS_NAME already exists"
    fi
    
    msg "Make fedora-based rootfs for $ROOTFS_NAME"
    
    rm -rf "$INSTALL_ROOT"
    mkdir -p "$INSTALL_ROOT"
    #get_password
    
    #root_password="xxxxxx"
    #utsname="$ROOTFS_NAME.local"
    
    ## we create local variables from the srvctl system variables to have an easy life with templates.
    release="$VERSION_ID"
    
    BASE_PKG_LIST="dnf initscripts passwd rsyslog vim-minimal openssh-server openssh-clients dhclient chkconfig rootfiles policycoreutils fedora-repos fedora-release"
    
    run dnf --releasever="$release" --installroot "$INSTALL_ROOT" -y --nogpgcheck install "$BASE_PKG_LIST" "$SRVCTL_PKG_LIST"
    exif "failed to build rootfs"
    
    ## srvctl addition
    ## nodjs has to be installed seperatley
    #if [ ! -z "$nodejs_rpm_url" ]
    #then
    #    msg "Install nodejs"
    #    dnf --installroot "$INSTALL_ROOT" -y --nogpgcheck install $nodejs_rpm_url
    #fi
    
    mkrootfs_root_ssh "$INSTALL_ROOT"
    
    return
    
    
}

function mkrootfs_root_ssh { ## needs rootfs
    
    local rootfs
    rootfs="$1"
    
    if [[ ! -d "$rootfs/root" ]]
    then
        err "No rootfs for setup_rootfs_ssh "
    else
        ## make root's key access
        mkdir -p -m 600 "$rootfs/root/.ssh"
        cat /root/.ssh/id_rsa.pub > "$rootfs/root/.ssh/authorized_keys"
        cat /root/.ssh/authorized_keys >> "$rootfs/root/.ssh/authorized_keys"
        chmod 600 "$rootfs/root/.ssh/authorized_keys"
        
        ## disable password authentication on ssh
        sed -i.bak "s/PasswordAuthentication yes/PasswordAuthentication no/g" "$rootfs/etc/ssh/sshd_config"
    fi
}
