#!/bin/bash

## @@@ destroy-ve VE
## @en Delete container with all its files
## &en Delete all files and all records regarding the VE.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
#authorize
container_user="$(get container "$ARG" user)"
container_reseller="$(get container "$ARG" reseller)"

msg "Container $ARG - $container_user ($container_reseller)"

if [[ $SC_USER == $container_user ]] || [[ $SC_USER == $container_reseller ]]
then
    sudomize
fi

if [[ $USER == root ]]
then
    
    local C
    C="$ARG"
    
    rm -fr /etc/systemd/system/machines.target.wants/srvctl-nspawn@"$C".service
    
    if [[ -f /etc/srvctl/containers/$C.service ]]
    then
        systemctl stop "$C"
        systemctl disable "$C"
    fi
    
    del container "$C"
    
    rm -fr /var/srvctl3/storage/static/"$C"
    
    ## https://www.cyberciti.biz/tips/nfs-stale-file-handle-error-and-solution.html
    
    for u in $(ls /home)
    do
        if [[ -d /home/"$u"/"$C" ]]
        then
            run umount -f /home/"$u"/"$C"/bindfs
            run rm -fr /home/"$u"/"$C"/bindfs
            run rm -fr /home/"$u"/"$C"
        fi
    done
    
    run sleep 3
    run machinectl terminate "$C"
    
    if [[ -d /srv/$C ]]
    then
        rm -fr "/srv/$C"
    fi
    
    msg "$C destroyed."
    
    
else
    err "$SC_USER has no access to $ARG"
    exit
fi
