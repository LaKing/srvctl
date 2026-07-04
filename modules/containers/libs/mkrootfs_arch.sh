#!/bin/bash

#[[ $SRVCTL ]] || exit
#[[ $SC_ROOTFS_DIR ]] || exit

function mkrootfs_arch_base { ## name packagelist
    
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
    
    msg "Make arch-based rootfs for $rootfs_name"
    
    run rm -rf "$rootfs_base"
    mkdir -p "$rootfs_base"
    
    pacman-key --init
    pacman-key --populate archlinux
    
    ## pacstrap -G -M -i -c -d /var/lib/machines/arch base
    run pacstrap -G -M -c -d "$rootfs_base" base base-devel inetutils
    if [ "$?" != "0" ]
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
    
    msg "Make arch-based rootfs for $rootfs_name complete"
    return
    
    
}