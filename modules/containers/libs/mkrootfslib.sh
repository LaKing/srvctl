#!/bin/bash

#[[ $SRVCTL ]] || exit
#[[ $SC_ROOTFS_DIR ]] || exit

function mkrootfs_fedora_base { ## N name
    
    ## this is my own version for rootfs creation
    local rootfs_name srvctl_pkg_list install_root
    
    rootfs_name="$1"
    srvctl_pkg_list="$2"
    install_root="$SC_ROOTFS_DIR/$rootfs_name"
    
    msg "Make fedora-based rootfs for $rootfs_name"
    
    run rm -rf "$install_root"
    mkdir -p "$install_root"
    #get_password
    
    #root_password="xxxxxx"
    #utsname="$rootfs_name.local"
    
    ## we create local variables from the srvctl system variables to have an easy life with templates.
    release="$VERSION_ID"
    
    base_pkg_list="dnf initscripts passwd rsyslog vim-minimal openssh-server openssh-clients dhclient chkconfig rootfiles policycoreutils fedora-repos fedora-release"
    
    run dnf --releasever="$release" --installroot "$install_root" -y --nogpgcheck install "$base_pkg_list" "$srvctl_pkg_list"
    exif "failed to build rootfs"
    
    ## srvctl addition
    ## nodjs has to be installed seperatley
    #if [ ! -z "$nodejs_rpm_url" ]
    #then
    #    msg "Install nodejs"
    #    dnf --installroot "$install_root" -y --nogpgcheck install $nodejs_rpm_url
    #fi
    
    mkrootfs_root_ssh "$install_root"
    
    ln -s /usr/local/share/srvctl/srvctl.sh "$install_root"/bin/sc
    ln -s /usr/local/share/srvctl/srvctl.sh "$install_root"/bin/srvctl
    
    chroot "$install_root" groupadd -r -g 101 srv
    chroot "$install_root" useradd -r -u 101 -g 101 -s /sbin/nologin -d /srv srv
    
    chroot "$install_root" groupadd -r -g 102 git
    chroot "$install_root" useradd -r -u 102 -g 102 -s /sbin/nologin -d /var/git git
    
    ## TODO - check if we need users and especially what UIDs to use ...
    #chroot "$install_root" groupadd -r -g 27 mysql
    #chroot "$install_root" useradd -r -u 27 -g 27 -s /sbin/nologin -d /var/lib/mysql mysql
    
    chroot "$install_root" groupadd -r -g 103 node
    chroot "$install_root" useradd -r -u 103 -g 103 -s /sbin/nologin -d /srv node
    
    chroot "$install_root" groupadd -r -g 104 codepad
    chroot "$install_root" useradd -r -u 104 -g 104 -s /sbin/nologin -d /srv/codepad codepad
    
    
    msg "Make fedora-based rootfs for $rootfs_name complete"
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
        #sed -i.bak "s/PasswordAuthentication yes/PasswordAuthentication no/g" "$rootfs/etc/ssh/sshd_config"
        
        update_container_sshd_config "$rootfs"
    fi
}
