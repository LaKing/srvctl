#!/bin/bash

## @@@ add-reseller USERNAME
## @en Add user as reseller to the host cluster
## &en Add user to the current cluster datastore and create it on the system.
## &en users will have default passwords, certificates, etc, ..

root_only

sudomize
argument username

##
##   Registers USERNAME as a reseller in the cluster datastore (users.json
##   with a reseller_id, via the datastore "new reseller" command) and
##   triggers regenerate_users (main.js) to provision the account. Root
##   only. Resellers own users and containers; by convention they get a
##   single-character username, which is what authlib checks to grant
##   reseller privileges.
##
##   Core of the reseller mechanics — deprecation candidate for v4 (G6),
##   but LIVE on production until the migration.
##

## sourced by run_command, so this runs in a function scope
## the datastore key is the lowercased argument
username="${ARG,,}"

## FIXME(v4): unanchored regex (no ^...$) — any string merely containing a
## valid 3+ char run passes, and it also never enforces the single-char
## reseller convention; anchor and share the validator with add-user.
if ! [[ "$username" =~ ([a-z_][a-z0-9_]{2,30}) ]]
then
    err "Invalid username: $username"
    exit 22
else

    if [[ "$(get user "$username" exist)" == true ]]
    then
        err "User $username already exist."
    else
        new reseller "$username"
        regenerate_users
    fi
fi
