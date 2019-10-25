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

container_user="$(get container "$C" user)"
exif
container_reseller="$(get container "$C" reseller)"
exif

if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then
    
    cfg container "$C" add_mapped_port "$OPAS"
    run systemctl stop "srvctl-nspawn@$C.service" --no-pager
    sleep 2
    run systemctl start "srvctl-nspawn@$C.service" --no-pager
    run systemctl status "srvctl-nspawn@$C.service" --no-pager
else
    exit
fi