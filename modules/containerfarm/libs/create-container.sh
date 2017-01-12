#!/bin/bash

function create_nspawn_container_filesystem() { ## C T
    
    local C T
    C="$1"
    T="$2"
    
    if [[ ! -d $SC_ROOTFS_DIR/$T ]]
    then
        err "No base for rootfs $T. Please run regenerate-rootfs."
        exit
    fi
    
    local rootfs
    rootfs="/srv/$C/rootfs"
    mkdir -p "$rootfs"
    
    printf "%s" "$T" > "/srv/$C/ctype"
    printf "%s" "$NOW" > "/srv/$C/creation-date"
    printf "%s" "$SC_USER" > "/srv/$C/creation-user"
    
    msg "Create $T nspawn container filesystem $C"
    
    ## copy the filesystem root
    run cp -R -p "$SC_ROOTFS_DIR/$T/*" "$rootfs"
    
    ## add user's keys
    cat "$SC_HOME/.ssh/authorized_keys" >> "$rootfs/root/.ssh/authorized_keys"
    
    ## end of function
}

function create_nspawn_container_network() { ## C T
    
    local C T
    C="$1"
    T="$2"
    
    local ip br
    ip="$(get container "$C" ip)" || exit
    br="$(get container "$C" br)" || exit
    
    msg "Create $T nspawn container network $C"
    msg "ip: $ip / br: $br"
    
    
    if [[ -z $ip ]] || [[ -z $br ]]
    then
        err "Zero-ip/br"
        exit 35
    fi
    
    ## -a ?
    
    local rootfs
    rootfs="/srv/$C/rootfs"
    mkdir -p "$rootfs"
    
    printf "%s" "$ip" > "/srv/$C/ipv4-address"
    printf "%s" "$br" > "/srv/$C/bridge"
    
    mkdir -p "$SC_MOUNTS_DIR/$C/etc/network"
    
    create_networkd_bridge "$br"
    create_nspawn_container_service "$C" "$br"
    create_nspawn_container_host0 "$C" "$br" "$ip"
    
    ## create container networking in the container
    if [[ ! -e "$rootfs"/etc/systemd/system/multi-user.target.wants/systemd-networkd.service ]]
    then
        ln -s /usr/lib/systemd/system/systemd-networkd.service "$rootfs"/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
    fi
    #ln -s /usr/lib/systemd/system/systemd-networkd.service "$rootfs"/etc/systemd/system/sockets.target.wants/systemd-networkd.socket
    
    
    ## end of function
}
