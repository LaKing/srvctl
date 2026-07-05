#!/bin/bash

## @en List container statuses

##
##   containers/commands/status.sh — container status, single or table.
##
##   With an argument: systemctl status of the container's nspawn unit
##   (or of the named service verbatim when /srv/$C/rootfs does not
##   exist) via service_action. Without: containers_status renders the
##   cluster-wide table (status.js — ping, IP, type, disk, user,
##   reseller, DNS flags).
##

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
