#!/bin/bash

## @@@ add-user USERNAME
## @en Add user to the host cluster
## &en Add user to database and create it on the system.
## &en users will have default passwords, certificates, etc, ..

## if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
## SC_USE_CONTAINERS

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
        new user "$username"
        regenerate_users
    fi
    
    reseller="$(get user "$username" reseller)"
    ntc "Reseller for $username is: $reseller"
    
fi
