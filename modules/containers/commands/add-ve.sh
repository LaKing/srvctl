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

local ip br
ip="$(get container "$C" ip)"
br="$(get container "$C" br)"

msg "Container $C
ip: $ip
br: $br
"

## -a ?
run cp -R -p "$ROOTFS_DIR/fedora" "$SRV/$C"

mkdir -p "$MOUNTS_DIR/$C/etc/network"

create_container_bridge "$br" "$C"
create_container_service "$br" "$C"

run systemctl start "$C" --no-pager
run systemctl status "$C" --no-pager
