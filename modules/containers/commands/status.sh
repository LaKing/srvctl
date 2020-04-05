#!/bin/bash

## @en List container statuses



if [[ $ARG ]]
then
    argument container-name
    authorize
    
    C="$ARG"
    
    if [[ -d /srv/$C/rootfs ]]
    then
        service_action "srvctl-nspawn@$C.service" status
    else
        service_action "$C" status
    fi
    return
fi

containers_status
