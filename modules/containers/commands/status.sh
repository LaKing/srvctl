#!/bin/bash

## @en List container statuses



if [[ $ARG ]]
then
    
    argument container-name
    authorize
    
    if [[ -d /srv/$ARG/rootfs ]]
    then
        service_action "srvctl-nspawn@$ARG.service" status
    else
        service_action "$ARG" status
    fi
    return
fi

containers_status
