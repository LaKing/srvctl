#!/bin/bash

function create_nspawn_container_filesystem() { ## C
    
    local C T
    C="$1"
    
    T="$(get container "$C" type)" || return
    
    ## this check is a redundant one...
    if [[ ! -d $SC_ROOTFS_DIR/$T ]]
    then
        err "INSTALLATION ERROR - rootfs $T not available"
        msg "root needs to run: srvctl regenerate rootfs"
        exit 66
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
    
    ## end of function
}
