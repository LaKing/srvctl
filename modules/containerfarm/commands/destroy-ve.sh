#!/bin/bash

## @@@ destroy-ve VE
## @en Delete container with all its files
## &en Delete all files and all records regarding the VE.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
authorize
sudomize

local C
C="$ARG"
if [[ -f /etc/srvctl/containers/$C.service ]]
then
    run systemctl stop "$C"
    run systemctl disable "$C"
    run rm -fr "/etc/srvctl/containers/$C.service"
    msg "$C service removed."
fi

cd /srv

if [[ "$(get container "$C" exist)" == true ]]
then
    del container "$C"
    exif
    msg "$C is removed from the datastore."
fi

if [[ -d /srv/$C ]]
then
    run rm -fr "/srv/$C"
    msg "$C files removed."
fi

msg "$C is destroyed."
