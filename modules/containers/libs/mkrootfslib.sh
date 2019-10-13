#!/bin/bash

#[[ $SRVCTL ]] || exit
#[[ $SC_ROOTFS_DIR ]] || exit

function mkrootfs_fedora_base { ## name packagelist
    
    ## this is my own version for rootfs creation
    local rootfs_name srvctl_pkg_list rootfs_base plus_pkg_list
    
    rootfs_name="$1"
    srvctl_pkg_list="$2"
    rootfs_base="$SC_ROOTFS_DIR/$rootfs_name"
    
    msg "Make fedora-based rootfs for $rootfs_name"
    
    run rm -rf "$rootfs_base"
    mkdir -p "$rootfs_base"
    #get_password
    
    #root_password="xxxxxx"
    #utsname="$rootfs_name.local"
    
    ## we create local variables from the srvctl system variables to have an easy life with templates.
    release="$VERSION_ID"
    
    
    base_pkg_list="dnf initscripts passwd rsyslog vim-minimal openssh-server openssh-clients dhclient chkconfig rootfiles policycoreutils fedora-repos fedora-release bash-completion"
    
    ## added systemd-container for docker support
    plus_pkg_list="hostname git nodejs gcc-c++ mc openssl postfix mailx sendmail unzip rsync wget firewalld"
    
    run dnf --releasever="$release" --installroot "$rootfs_base" -y --nogpgcheck install "$base_pkg_list" "$plus_pkg_list" "$srvctl_pkg_list"
    exif "failed to build rootfs"
    
    ## srvctl addition
    ## nodjs has to be installed seperatley
    #if [ ! -z "$nodejs_rpm_url" ]
    #then
    #    msg "Install nodejs"
    #    dnf --installroot "$rootfs_base" -y --nogpgcheck install $nodejs_rpm_url
    #fi
    
    mkrootfs_root_ssh "$rootfs_base"
    
    ln -s /usr/local/share/srvctl/srvctl.sh "$rootfs_base"/bin/sc
    ln -s /usr/local/share/srvctl/srvctl.sh "$rootfs_base"/bin/srvctl
    
    chroot "$rootfs_base" groupadd -r -g 101 srv
    chroot "$rootfs_base" useradd -r -u 101 -g 101 -s /sbin/nologin -d /srv srv
    
    chroot "$rootfs_base" groupadd -r -g 102 git
    chroot "$rootfs_base" useradd -r -u 102 -g 102 -s /sbin/nologin -d /var/git git
    
    ## TODO - check if we need users and especially what UIDs to use ...
    #chroot "$rootfs_base" groupadd -r -g 27 mysql
    #chroot "$rootfs_base" useradd -r -u 27 -g 27 -s /sbin/nologin -d /var/lib/mysql mysql
    
    chroot "$rootfs_base" groupadd -r -g 103 node
    chroot "$rootfs_base" useradd -r -u 103 -g 103 -s /sbin/nologin -d /srv node
    
    chroot "$rootfs_base" groupadd -r -g 104 codepad
    chroot "$rootfs_base" useradd -r -u 104 -g 104 -s /bin/bash -d /var/codepad codepad
    
    run mkdir -p "$rootfs_base"/etc/systemd/system/multi-user.target.wants/
    run mkdir -p "$rootfs_base"/rootfs/etc/postfix
    
    run ln -s /usr/lib/systemd/system/postfix.service "$rootfs_base"/etc/systemd/system/multi-user.target.wants/postfix.service
    cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-main.cf" > "$rootfs_base"/etc/postfix/main.cf
    
    sed -i -e 's/info/#info/g' "$rootfs_base"/etc/aliases
    rm -fr "$rootfs_base"/aliases.db
    chroot "$rootfs_base" newaliases
    
    if [[ $rootfs_name == mail ]]
    then
        cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-mail.cf" > "$rootfs_base"/etc/postfix/main.cf
        run ln -s /usr/lib/systemd/system/dovecot.service "$rootfs_base"/etc/systemd/system/multi-user.target.wants/dovecot.service
    fi
    
    run_hooks mkrootfs_fedora
    
    msg "Make fedora-based rootfs for $rootfs_name complete"
    return
    
    
}

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
        cat /root/.ssh/id_rsa.pub > "$rootfs/root/.ssh/authorized_keys"
        cat /root/.ssh/authorized_keys >> "$rootfs/root/.ssh/authorized_keys"
        chmod 600 "$rootfs/root/.ssh/authorized_keys"
        
        ## disable password authentication on ssh
        #sed -i.bak "s/PasswordAuthentication yes/PasswordAuthentication no/g" "$rootfs/etc/ssh/sshd_config"
        
        update_container_sshd_config "$rootfs"
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

