#!/bin/bash

## @@@ add-user USERNAME
## @en Add user to the current cluster
## &en Create the user in the current cluster datastore and create it on the system.
## &en users will have default passwords, certificates, etc, ..

reseller_only

sudomize
argument username

local username reseller
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
        new user "$username"
        regenerate_users
    fi
    
    reseller="$(get user "$username" reseller)"
    ntc "Reseller for $username is: $reseller"
    
fi
