#!/bin/bash

## @@@ destroy VE
## @en Delete container with all its files
## &en Delete all files and all records regarding the VE.

argument container

local C
C="$ARG"

systemctl stop "$C"
systemctl disable "$C"

if [[ -d $SRV/$C ]]
then
    rm -fr "$SRV/$C"
fi

del container "$C"

msg "$C destroyed."
