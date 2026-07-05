#!/bin/bash

## @@@ add-ve-user VE USERNAME
## @en Add user to the current cluster
## &en Create the user in the current cluster datastore and create it on the system.
## &en users will have default passwords, certificates, etc, ..

reseller_only
hs_only

sudomize
argument container-name

##
##   containers/commands/add-ve-user.sh — grant a (possibly new) user
##   access to a container.
##
##   Reseller-gated, host-side. Lowercases USERNAME and validates it
##   (exit 22 on mismatch). If the user does not exist in the datastore
##   yet it is created ('new user') and system users are regenerated
##   (usersonhost module). Then the user is appended to the container's
##   users list and the regenerate hook rewrites all configs.
##

C="$ARG"
username="${OPA,,}"

## FIXME(v4): unanchored regex — =~ matches a substring, so any name
## containing one lowercase letter passes (e.g. 'A!b'); anchor with ^...$
## to actually enforce the 2-30 char pattern.
if ! [[ "$username" =~ (([a-z]|[a-z_][a-z0-9_]{2,30})) ]]
then
    err "Invalid username: $username"
    exit 22
fi

if [[ "$(get user "$username" exist)" == true ]]
then
    ntc "User $username already exist."
else
    new user "$username"
    regenerate_users
fi

reseller="$(get user "$username" reseller)"
ntc "Reseller for $username is: $reseller"

add container "$C" user "$username"

run_hook regenerate
