#!/bin/bash

## @@@ add-ve NAME
## @en Add a fedora container.
## &en Generic container for customization.
## &en Contains basic packages.

[[ $SRVCTL ]] || exit

sudomize

local C

C="$ARG"



## check for a mistake
if [[ -d $SRV/$C ]]
then
    err "$SRV/$C already exists! Exiting"
    exit 11
fi

## -a ?
run cp -R -p "$ROOTFS_DIR/fedora" "$SRV/$C"

mkdir -p "$MOUNTS_DIR/$C/etc/network"

create_container_service "$C"

run systemctl start "$C" --no-pager
run systemctl status "$C" --no-pager
