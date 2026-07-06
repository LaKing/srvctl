#!/bin/bash

## @@@ map-port VE [udp] PORT DESCRIPTION
## @en Map a tcp port to the host.
## &en Mapping container tcp or udp ports directly to the host.
## &en Port number must be between 1 and 65535

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container-name
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

## WP-E.2: root passes, the owner/reseller escalates, everyone else is denied
## — evaluated before any datastore write or container restart. (Was: an
## unconditional sudomize for everyone, then an owner-check that wrongly denied
## even root unless it owned the container.)
owner_only container "$C"

cfg container "$C" add_mapped_port "$OPAS"
run systemctl stop "srvctl-nspawn@$C.service" --no-pager
sleep 2
run systemctl start "srvctl-nspawn@$C.service" --no-pager
run systemctl status "srvctl-nspawn@$C.service" --no-pager