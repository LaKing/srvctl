#!/bin/bash

## @@@ add-user USERNAME
## @en Add user to the current cluster
## &en Create the user in the current cluster datastore and create it on the system.
## &en users will have default passwords, certificates, etc, ..

reseller_only

sudomize
argument username

##
##   Registers USERNAME in the cluster datastore (users.json, via the
##   datastore "new user" command) and triggers regenerate_users, which
##   runs main.js: system account, password, ssh keys, client certificate
##   and container share mounts. Restricted to resellers (the single-char
##   SC_USER convention) and root; self-elevates through sudo otherwise.
##
##   Part of the reseller mechanics — deprecation candidate for v4 (G6),
##   but LIVE on production until the migration.
##

## sourced by run_command, so this runs in a function scope
## the datastore key is the lowercased argument
username="${ARG,,}"

## FIXME(v4): unanchored regex (no ^...$) — any string merely containing a
## valid 3+ char run passes (e.g. "a b!"), and the raw value flows into the
## datastore key and later into adduser; anchor and share the validator.
if ! [[ "$username" =~ ([a-z_][a-z0-9_]{2,30}) ]]
then
    err "Invalid username: $username"
    exit 22
else

    if [[ "$(get user "$username" exist)" == true ]]
    then
        ntc "User $username already exist."
    else
        new user "$username"
        regenerate_users
    fi

    ## for a reseller caller the datastore assigns their own id
    reseller="$(get user "$username" reseller)"
    ntc "Reseller for $username is: $reseller"

fi
