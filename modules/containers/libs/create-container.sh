#!/bin/bash

##
##   containers/libs/create-container.sh — /srv/$C skeleton and rootfs
##   instantiation from a base image.
##
##   Used by add_ve, recreate-ve and the regenerate reconciliation
##   (check_container_directories / check_container_database).
##

function create_container_configuration_files() {
    local C T
    C="$1"

    T="$(get container "$C" type)"

    msg "Create $T nspawn container configuration files $C"


    mkdir -p "/srv/$C"

    ## TODO - rather add to datastore
    printf "%s" "$NOW" > "/srv/$C/creation-date"
    printf "%s" "$SC_USER" > "/srv/$C/creation-user"

}


function create_nspawn_container_filesystem() { ## C T
    
    local C T
    C="$1"
    T="$2"
    
    if [[ -f /srv/$C/rootfs/etc/os-release ]]
    then
        ntc "$C is already a valid container"
        return
    fi
    
    if [[ $T ]]
    then
        msg "Using the $T rootfs"
    else
        T="$(get container "$C" type)"
    fi
    
    msg "Create $T nspawn container filesystem $C"

    ## this check is a redundant one...
    ## FIXME(v4): with an empty type (unknown /srv dir reconciled by
    ## check_container_directories) the path degenerates to
    ## "$SC_ROOTFS_DIR/" — the -d test passes and the copy below globs
    ## ALL base images into the new rootfs (and with no match creates a
    ## literal '*' entry); validate $T is non-empty and a known image.
    if [[ ! -d $SC_ROOTFS_DIR/$T ]]
    then
        err "INSTALLATION ERROR - rootfs $T not available for $C"
        msg "root needs to run: srvctl regenerate rootfs"
        exit 66
    fi

    local rootfs
    rootfs="/srv/$C/rootfs"
    mkdir -p "$rootfs"

    ## copy the filesystem root (run word-splits, so the quoted * still
    ## globs when the command line is executed)
    run cp -R -p "$SC_ROOTFS_DIR/$T/*" "$rootfs"

    printf '%s' "$C" > "$rootfs/etc/hostname"

    ## end of function
}