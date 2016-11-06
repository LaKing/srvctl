#!/bin/bash

## @@@ destroy VE
## @en Delete container with all its files
## &en Delete all files and all records regarding the VE.

argument container

local C
C="$ARG"

run systemctl stop "$C"
run systemctl disable "$C"

if [[ -d $SRV/$C ]]
then
    run rm -fr "$SRV/$C"
fi

del container "$C"

msg "$C destroyed."
