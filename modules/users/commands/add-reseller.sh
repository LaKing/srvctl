#!/bin/bash

## @@@ add-reseller USERNAME
## @en Add user to the systems
## &en Add user to database and create it on the system.
## &en users will have default passwords, certificates, etc, ..

root_only
hs_only
argument username

local username password reseller
username="${ARG,,}"

if [[ "$username" =~ ([a-z_][a-z0-9_]{2,30}) ]]
then
    msg "Adding user $username"
else
    err "Invalid username: $username"
    exit 22
fi

# shellcheck disable=SC2154
if ! $SC_USE_datastore
then
    err "Datastore not available."
    exit 23
fi

if [[ "$(get user "$username" exist)" == true ]]
then
    ntc "User $username already exist."
    exit 24
fi

new reseller "$username"

regenerate_all_hosts

