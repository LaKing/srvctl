#!/bin/bash

##
##   containers/libs/mkrootfs_debian.sh — build a debian base image via
##   debootstrap (stable). Same contract as mkrootfs_fedora.sh minus the
##   fedora-specific users/mail setup. No live caller — only reachable
##   through commented-out lines in hooks/regenerate_rootfs.sh.
##

function mkrootfs_debian_base { ## name

    ## this is my own version for rootfs creation
    local rootfs_name rootfs_base

    if [[ $1 ]]
    then
        rootfs_name="$1"
        rootfs_base="$SC_ROOTFS_DIR/$rootfs_name"
    else
        err "No name for mkrootfs"
        return
    fi
    
    msg "Make debian-based rootfs for $rootfs_name"
    
    run rm -rf "$rootfs_base"
    mkdir -p "$rootfs_base"
    
    if ! run debootstrap --include=ssh,systemd,dbus,libpam-systemd,mc,nodejs stable "$rootfs_base"
    then
        rm -fr "$rootfs_base"
        err "Failed to create $rootfs_name"
        return
    fi

    mkrootfs_root_ssh "$rootfs_base"
    
    ln -s /usr/local/share/srvctl/srvctl.sh "$rootfs_base"/bin/sc
    ln -s /usr/local/share/srvctl/srvctl.sh "$rootfs_base"/bin/srvctl
    
    run mkdir -p "$rootfs_base"/etc/systemd/system/multi-user.target.wants/
    ## create container networking in the container
    
    run ln -s /usr/lib/systemd/system/systemd-networkd.service "$rootfs_base"/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
    run ln -s /usr/lib/systemd/system/systemd-resolved.service "$rootfs_base"/etc/systemd/system/multi-user.target.wants/systemd-resolved.service
    
    
    run_hooks mkrootfs_debian
    
    msg "Make debian-based rootfs for $rootfs_name complete"
    return
    
    
}