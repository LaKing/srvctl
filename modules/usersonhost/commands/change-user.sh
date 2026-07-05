#!/bin/bash

## @@@ change-user VE USERNAME
## @en Move container to a different user
## &en Move container to be owned by a different user. This invoves a change in the IP adress, thus requires a restart of the container.

reseller_only

sudomize
argument container

##
##   STUB — validates its arguments, reports the target user's reseller,
##   then errors out with "not implemented". The intent is to reassign
##   container VE to USERNAME, which implies a new (uid-derived) IP
##   address and a container restart. Gated to resellers/root like the
##   rest of the reseller mechanics — deprecation candidate for v4 (G6),
##   but the command surface must stay until the migration.
##

# shellcheck disable=SC2034
## C stays unused until the stub is implemented
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

## users without a reseller in the datastore belong to root
reseller="$(get user "$username" reseller)"
if [[ -z $reseller ]]
then
    reseller=root
fi
ntc "Reseller for $username is: $reseller"

## FIXME(v4): unimplemented stub — implement the reassignment (datastore
## user change, IP/uid update, container restart) or drop the command
err "DEV (not implemented - yet.)"
