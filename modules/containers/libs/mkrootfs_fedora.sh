#!/bin/bash

##
##   containers/libs/mkrootfs_fedora.sh — build the fedora base image.
##
##   mkrootfs_fedora_base (used by hooks/regenerate_rootfs.sh and the
##   codepad module) dnf-installs a fedora rootfs at the HOST's
##   VERSION_ID under $SC_ROOTFS_DIR/<name>, then bakes in the srvctl
##   contracts: root ssh access + sshd_config (mkrootfslib.sh), sc/srvctl
##   symlinks, the fixed uid/gid users srv=801 git=802 node=803
##   codepad=804, postfix/dovecot enabled with the module templates, and
##   finally 'run_hooks mkrootfs_fedora' (codepad and firewalld modules
##   customize the image there). The image is REMOVED and rebuilt from
##   scratch on every call.
##

function mkrootfs_fedora_base { ## name packagelist

    ## this is my own version for rootfs creation
    local rootfs_name srvctl_pkg_list rootfs_base plus_pkg_list

    if [[ $1 ]]
    then
        rootfs_name="$1"
        srvctl_pkg_list="$2"
        rootfs_base="$SC_ROOTFS_DIR/$rootfs_name"
    else
        err "No name for mkrootfs"
        return
    fi
    
    msg "Make fedora-based rootfs for $rootfs_name"

    run rm -rf "$rootfs_base"
    mkdir -p "$rootfs_base"

    ## we create local variables from the srvctl system variables to have an easy life with templates.
    release="$VERSION_ID"


    base_pkg_list="dnf initscripts passwd rsyslog vim-minimal openssh-server openssh-clients dhclient chkconfig rootfiles policycoreutils fedora-repos fedora-release bash-completion"

    ## added systemd-container for docker support
    plus_pkg_list="hostname git nodejs gcc-c++ mc openssl postfix mailx sendmail dovecot unzip rsync wget firewalld cyrus-sasl cyrus-sasl-lib cyrus-sasl-plain cyrus-sasl-md5"

    if ! run "dnf --use-host-config --releasever=$release --installroot $rootfs_base -y --nogpgcheck install $base_pkg_list $plus_pkg_list $srvctl_pkg_list"
    then
        rm -fr "$rootfs_base"
        err "Failed to create $rootfs_name"
        return
    fi

    mkrootfs_root_ssh "$rootfs_base"
    
    ln -s /usr/local/share/srvctl/srvctl.sh "$rootfs_base"/bin/sc
    ln -s /usr/local/share/srvctl/srvctl.sh "$rootfs_base"/bin/srvctl
    
    chroot "$rootfs_base" groupadd -r -g 801 srv
    chroot "$rootfs_base" useradd -r -u 801 -g 801 -s /sbin/nologin -d /srv srv
    
    chroot "$rootfs_base" groupadd -r -g 802 git
    chroot "$rootfs_base" useradd -r -u 802 -g 802 -s /sbin/nologin -d /var/git git

    ## TODO - check if we need users and especially what UIDs to use ...

    chroot "$rootfs_base" groupadd -r -g 803 node
    chroot "$rootfs_base" useradd -r -u 803 -g 803 -s /sbin/nologin -d /srv node
    
    chroot "$rootfs_base" groupadd -r -g 804 codepad
    chroot "$rootfs_base" useradd -r -u 804 -g 804 -s /bin/bash -d /var/codepad codepad
    
    run mkdir -p "$rootfs_base"/etc/systemd/system/multi-user.target.wants/
    ## FIXME(v4): typo'd path creates a junk rootfs/etc/postfix directory
    ## INSIDE the base image (intended $rootfs_base/etc/postfix, which the
    ## postfix package already provides).
    run mkdir -p "$rootfs_base"/rootfs/etc/postfix

    run ln -s /usr/lib/systemd/system/postfix.service "$rootfs_base"/etc/systemd/system/multi-user.target.wants/postfix.service
    cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-main.cf" > "$rootfs_base"/etc/postfix/main.cf
    
    sed -i -e 's/info/#info/g' "$rootfs_base"/etc/aliases
    rm -fr "$rootfs_base"/aliases.db
    chroot "$rootfs_base" newaliases
    
    ## create container networking in the container
    ln -s /usr/lib/systemd/system/systemd-networkd.service "$rootfs_base"/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
    ln -s /usr/lib/systemd/system/systemd-resolved.service "$rootfs_base"/etc/systemd/system/multi-user.target.wants/systemd-resolved.service
    
    ## (duplicate of the ve-main.cf install a few lines above — harmless)
    cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-main.cf" > "$rootfs_base"/etc/postfix/main.cf
    sed_file "$rootfs_base"/etc/pki/dovecot/dovecot-openssl.cnf "default_bits = 1024" "default_bits = 4096"
    grep 'default_bits' "$rootfs_base"/etc/pki/dovecot/dovecot-openssl.cnf
    run ln -s /usr/lib/systemd/system/dovecot.service "$rootfs_base"/etc/systemd/system/multi-user.target.wants/dovecot.service
    
    run_hooks mkrootfs_fedora
    
    msg "Make fedora-based rootfs for $rootfs_name complete"
    return
    
    
}