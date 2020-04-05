#!/bin/bash

## @@@ destroy-ve VE
## @en Delete container with all its files
## &en Delete all files and all records regarding the VE.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
#authorize

if [[ "$(get container "$ARG" exist)" == false ]]
then
    err "Container does not exist."
    exit 0
fi

container_user="$(get container "$ARG" user)"
container_reseller="$(get container "$ARG" reseller)"

msg "Container $ARG - $container_user ($container_reseller)"

if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then
    sudomize
fi

if [[ $SC_ROOT ]]
then
    
    C="$ARG"
    
    rm -fr /etc/systemd/system/machines.target.wants/srvctl-nspawn@"$C".service
    
    if [[ -f /etc/srvctl/containers/$C.service ]]
    then
        run systemctl stop "$C"
        run systemctl disable "$C"
        rm -f /etc/srvctl/containers/"$C".service
    fi
    
    del container "$C"
    
    rm -fr /var/srvctl3/storage/static/"$C"
    
    ## https://www.cyberciti.biz/tips/nfs-stale-file-handle-error-and-solution.html
    
    for uh in /home/*
    do
        if [[ -d "$uh"/"$C" ]]
        then
            for mp in "$uh"/"$C"/*
            do
                run umount -f "$mp"
                run rm -fr "$mp"
            done
            run rm -fr "$uh"/"$C"
        fi
    done
    
    run sleep 3
    
    ## TODO check if it is running
    if run machinectl status "$C" 2> /dev/null
    then
        run machinectl terminate "$C"
        run machinectl kill "$C"
    fi
    
    while [[ -d /srv/$C ]]
    do
        rm -fr "/srv/$C"
        if [[ -d /srv/$C ]]
        then
            ntc "$C has still a folder ..."
            sleep 3
        fi
    done
    
    msg "$C destroyed."
    
    
else
    err "$SC_USER has no access to $ARG"
    exit
fi
