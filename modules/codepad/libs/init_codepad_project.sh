#!/bin/bash

function init_codepad_project { ## Container
    
    local C C_uid codepad_uid
    C="$1"
    
    C_uid="$(get container "$C" uid)"
    
    msg "Init codepad project $C with uid $C_uid"
    
    rm -fr /srv/"$C"/rootfs/var/codepad/.ssh/*
    ssh-keygen -t ecdsa -f /srv/"$C"/rootfs/var/codepad/.ssh/id_ecdsa -N '' -C "codepad@$C $NOW"
    cat /srv/"$C"/rootfs/var/codepad/.ssh/id_ecdsa.pub > /srv/"$C"/rootfs/var/codepad/.ssh/authorized_keys
    echo "" >> /srv/"$C"/rootfs/root/.ssh/authorized_keys
    cat /srv/"$C"/rootfs/var/codepad/.ssh/id_ecdsa.pub >> /srv/"$C"/rootfs/root/.ssh/authorized_keys

    codepad_uid=$(( C_uid + 804 ))
    
    run chown -R "$codepad_uid:$codepad_uid" /srv/"$C"/rootfs/var/codepad
    
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