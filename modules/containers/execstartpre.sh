#!/bin/bash

## this script can run outside of srvctl! It will get invoked over systemd units
# shellcheck disable=SC2034
C="$1"

if [[ -f /srv/$C/hosts ]] && [[ -f /srv/$C/network/80-container-host0.network ]] && [[ -f /srv/$C/$C.nspawn ]]
then
    exit 0
else
    echo "create_container_config $C"
    exit 15
fi
