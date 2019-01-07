#!/bin/bash

## @@@ change-user VE USERNAME
## @en Move container to a different user
## &en Move container to be owned by a different user. This invoves a change in the IP adress, thus requires a restart of the container.

reseller_only

sudomize
argument container

#local C username reseller
# shellcheck disable=SC2034

C="$ARG"
username="$OPA"

if [[ -z "$username" ]]
then
    err "Need a new username"
    exit 22
fi


if [[ "$(get user "$username" exist)" != true ]]
then
    err "User $username does not exist."
    exit 23
fi

reseller="$(get user "$username" reseller)"
if [[ -z $reseller ]]
then
    reseller=root
fi
ntc "Reseller for $username is: $reseller"

#TODO implement it
err "DEV (not implemented - yet.)"