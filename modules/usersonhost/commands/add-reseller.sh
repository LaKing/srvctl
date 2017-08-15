#!/bin/bash

## @@@ add-reseller USERNAME
## @en Add user as reseller to the host cluster
## &en Add user to the current cluster datastore and create it on the system.
## &en users will have default passwords, certificates, etc, ..

root_only

sudomize
argument username

local username password reseller
username="${ARG,,}"

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
