#!/bin/bash

## @en List container statuses

##
##   containers/commands/status.sh — container status, single or table.
##
##   With an argument: systemctl status of the container's nspawn unit
##   (or of the named service verbatim when /srv/$C/rootfs does not
##   exist) via service_action. Without: containers_status renders the
##   cluster-wide table (status.js — ping, IP, type, disk, user,
##   reseller, DNS flags). A domain-only record is shown as such.
##

if [[ $ARG ]]
then
    argument container-name

    C="$ARG"

    if [[ $(get container "$C" domain_only 2> /dev/null) == true ]]
    then
        msg "$C is a domain-only record (retired with retire-ve): web $(get container "$C" web_ve 2> /dev/null || echo none), mail $(get container "$C" mail_ve 2> /dev/null || echo none)"
        return
    fi

    if [[ -d /srv/$C/rootfs ]]
    then
        service_action "srvctl-nspawn@$C.service" status
    else
        service_action "$C" status
    fi
    return
fi

containers_status
