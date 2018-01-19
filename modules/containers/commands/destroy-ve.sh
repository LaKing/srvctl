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
    if [[ -f /etc/srvctl/containers/$C.service ]]
    then
        systemctl stop "$C"
        systemctl disable "$C"
    fi
    
    if [[ -d /srv/$C ]]
    then
        rm -fr "/srv/$C"
    fi
    
    del container "$C"
    
    rm -fr /var/srvctl3/storage/static/"$C"
    
    run umount /home/*/"$C"/bindfs
    run rmdir /home/*/"$C"/bindfs
    run rmdir /home/*/"$C"
    
    run sleep 3
    run machinectl terminate "$C"
    
    msg "$C destroyed."
    
    
else
    err "$SC_USER has no access to $ARG"
    exit
fi
