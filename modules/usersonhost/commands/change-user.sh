#!/bin/bash

## @@@ change-user VE USERNAME
## @en Move container to a different user
## &en Move container to be owned by a different user. This invoves a change in the IP adress, thus requires a restart of the container.

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
root_only

##
##   STUB — validates its arguments, then ends with "not implemented". The
##   intent is to reassign container VE to USERNAME, which implies a new
##   address (10.HOSTNET.USER_ID.x) and a container restart.
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

## FIXME(v4): unimplemented stub — implement the reassignment (datastore
## user change, address update, container restart) or drop the command
err "change-user is not implemented and changes nothing."
exit 1
