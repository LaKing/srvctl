#!/bin/bash

## @@@ map-port VE [udp] PORT DESCRIPTION
## @en Map a tcp port to the host.
## &en Mapping container tcp or udp ports directly to the host.
## &en Port number must be between 1 and 65535

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container-name
authorize
sudomize
C="$ARG"

##
##   containers/commands/map-port.sh — publish a container tcp/udp port
##   on the host.
##
##   Stores the mapping in the datastore (cfg container add_mapped_port
##   parses "$OPAS": optional 'udp', port number, free-form description);
##   the nspawn config rendered from the datastore picks it up on the
##   stop+start cycle below (nspawn units cannot restart, systemd#2809).
##

container_user="$(get container "$C" user)"
exif
container_reseller="$(get container "$C" reseller)"
exif

## only the container owner or its reseller may map ports
if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then

    cfg container "$C" add_mapped_port "$OPAS"
    run systemctl stop "srvctl-nspawn@$C.service" --no-pager
    sleep 2
    run systemctl start "srvctl-nspawn@$C.service" --no-pager
    run systemctl status "srvctl-nspawn@$C.service" --no-pager
else
    ## WP-E.1: was a silent bare exit (status 0). The owner-check compares
    ## SC_USER (preserved across sudomize), so a root-but-not-owner caller
    ## (post-escalation) is denied here too.
    err "$SC_USER has no access to $C"
    exit 44
fi