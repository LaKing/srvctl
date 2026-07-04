#!/bin/bash

## @@@ backup-ve VE
## @en backup container with all its files
## &en Create a system-backup of the container

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
authorize

if [[ "$(get container "$ARG" exist)" == false ]]
then
    err "Container does not exist."
    exit 0
fi

container_user="$(get container "$ARG" user)"
container_reseller="$(get container "$ARG" reseller)"

msg "Container $ARG - $container_user ($container_reseller)"

if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then
    sudomize
fi

backup_ve "$ARG"