#!/bin/bash

## special services
# shellcheck disable=SC2154

## TODO check if user is reseller or user of service


#if [[ $op == "enable" ]] && [[ -f "/etc/srvctl/containers/$service.service" ]] && $IS_ROOT
#then
#    run systemctl enable "/etc/srvctl/containers/$service.service"
#    run systemctl start "$service.service"
#    exit 0
#fi

if [[ -z "$service" ]] && [[ $op == 'restart' ]]
then
    # shellcheck source=/usr/local/share/srvctl/modules/containers/commands/regenerate.sh
    source "$SC_INSTALL_DIR/modules/containers/commands/regenerate.sh"
    exit_0
fi

if [[ -d /srv/$service/rootfs ]]
then
    if $SC_ROOT
    then
        if [[ $SC_USER == $(get container "$service" user) ]] || [[ $SC_USER == $(get container "$service" reseller) ]] || $SC_ROOT
        then
            msg "AUTH-OK $SC_USER has acceess to $service"
        else
            err "AUTH-ERROR $SC_USER has no access to $service"
            exit 142
        fi
    else
        sudomize
    fi
    ## this is the service name actually for a container
    service="srvctl-nspawn@$service"
    
    ## containers cant be restarted, they need to be stopped and started then
    ## https://github.com/systemd/systemd/issues/2809
    if [[ $op == restart ]]
    then
        run systemctl stop "$service"
        run sleep 1
    fi
fi


## all-containers
if [[ $service == all-containers ]] && [[ ! -z "$op" ]] && [[ -f "/etc/systemd/system/srvctl-nspawn@.service" ]]
then
    sudomize
    
    all_containers "$op"
    exit_0
fi
