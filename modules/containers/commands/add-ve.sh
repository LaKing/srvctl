#!/bin/bash

## @@@ add-ve NAME
## @en Add a fedora container.
## &en Generic container for customization.
## &en Contains basic packages.

[[ $SRVCTL ]] || exit

argument container-name
sudomize
authorize

local C
C="$ARG"

if [[ "$(get container "$C" exist)" == true ]]
then
    err "$C already exists in the system! Exiting"
    exit 11
fi

## check for a mistake
if [[ -d $SRV/$C ]]
then
    err "$SRV/$C already exists! Exiting"
    exit 11
fi

put container "$C"

local ip br
ip="$(get container "$C" ip)"
br="$(get container "$C" br)"

msg "Container $C
ip: $ip
br: $br
"

if [[ -z $ip ]] || [[ -z $br ]]
then
    err "Zero-ip/br"
    exit 35
fi

## -a ?
run cp -R -p "$ROOTFS_DIR/fedora" "$SRV/$C"

mkdir -p "$MOUNTS_DIR/$C/etc/network"

create_container_bridge "$C" "$br"
create_container_service "$C" "$br"
create_container_host0 "$C" "$br" "$ip"

run systemctl start "$C" --no-pager
run systemctl status "$C" --no-pager
