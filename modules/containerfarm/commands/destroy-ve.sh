#!/bin/bash

## @@@ destroy-ve VE
## @en Delete container with all its files
## &en Delete all files and all records regarding the VE.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container

local C
C="$ARG"
if [[ -f /etc/srvctl/containers/$C.service ]]
then
    run systemctl stop "$C"
    run systemctl disable "$C"
    run rm -fr "/etc/srvctl/containers/$C.service"
fi

if [[ -d /srv/$C ]]
then
    run rm -fr "/srv/$C"
fi

del container "$C"

msg "$C destroyed."
