#!/bin/bash

##
##   init_codepad_project CONTAINER — per-container codepad init, run on
##   the host against /srv/$C/rootfs after the container was created from
##   the codepad template. Regenerates the codepad SSH keypair, grants
##   the codepad user root SSH access inside the container (intentional
##   for -devel containers), uid-shifts /var/codepad ownership for
##   nspawn PrivateUsers, and links the users share and the boilerplate
##   project. Used by the add-codepad command and the add_ve_codepad hook.
##

function init_codepad_project { ## Container

    local C C_uid codepad_uid
    C="$1"

    C_uid="$(get container "$C" uid)"

    msg "Init codepad project $C with uid $C_uid"

    ## fresh keypair on every init; the pubkey also becomes the codepad
    ## user's own authorized_keys and root access inside the container
    rm -fr /srv/"$C"/rootfs/var/codepad/.ssh/*
    ssh-keygen -t ecdsa -f /srv/"$C"/rootfs/var/codepad/.ssh/id_ecdsa -N '' -C "codepad@$C $NOW"
    cat /srv/"$C"/rootfs/var/codepad/.ssh/id_ecdsa.pub > /srv/"$C"/rootfs/var/codepad/.ssh/authorized_keys
    echo "" >> /srv/"$C"/rootfs/root/.ssh/authorized_keys
    cat /srv/"$C"/rootfs/var/codepad/.ssh/id_ecdsa.pub >> /srv/"$C"/rootfs/root/.ssh/authorized_keys

    ## host-side uid of the in-container codepad user: 804 must stay in
    ## sync with 'useradd -r -u 804 codepad' in the fedora rootfs build
    ## (containers/libs/mkrootfs_fedora.sh)
    codepad_uid=$(( C_uid + 804 ))

    run chown -R "$codepad_uid:$codepad_uid" /srv/"$C"/rootfs/var/codepad

    ## host path, valid in-container via the BindReadOnly mount emitted
    ## by datastore/lib.js
    run ln -s /var/srvctl3/share/containers/"$C"/users /srv/"$C"/rootfs/var/codepad/users

    ## our default codepad project is the boilerplate
    if [[ -d /usr/local/share/boilerplate ]]
    then
        msg "Adding boilerplate to codepad $C"

        mkdir -p /srv/"$C"/rootfs/srv/codepad-project
        ln -s /usr/local/share/boilerplate/@boilerplate /srv/"$C"/rootfs/srv/codepad-project/@boilerplate
    fi


    run_hook add_codepad_project

}
