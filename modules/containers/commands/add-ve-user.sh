#!/bin/bash

## @@@ add-ve-user VE USERNAME
## @en Add user to the current cluster
## &en Create the user in the current cluster datastore and create it on the system.
## &en users will have default passwords, certificates, etc, ..

reseller_only
hs_only

sudomize
argument container-name

#local username reseller
C="$ARG"
username="${OPA,,}"

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
