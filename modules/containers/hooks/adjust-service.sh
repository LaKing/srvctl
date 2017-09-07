#!/bin/bash

## special services
# shellcheck disable=SC2154

#if [[ $op == "enable" ]] && [[ -f "/etc/srvctl/containers/$service.service" ]] && $IS_ROOT
#then
#    run systemctl enable "/etc/srvctl/containers/$service.service"
#    run systemctl start "$service.service"
#    exit 0
#fi

if [[ -d /srv/$service ]]
then
    ## this is the service name actually for a container
    service="srvctl-nspawn@$service"
    
    ## containers cant be restarted, they need to be stopped and started then
    if [[ $op == restart ]]
    then
        run systemctl stop "$service"
        run sleep 1
    fi
fi


## special services
if [[ $service == containers ]] && [[ ! -z "$op" ]] && [[ -f "/etc/systemd/system/srvctl-nspawn@.service" ]] && $IS_ROOT
then
    
    ## must have conf
    for c in /srv/*/rootfs
    do
        local C="${c:5: -7}"
        msg "$C"
        if [[ $op == restart ]]
        then
            run systemctl stop "srvctl-nspawn@$C"
            run sleep 1
        fi
        service_action "srvctl-nspawn@$C" "$op"
    done
    return 0
fi
