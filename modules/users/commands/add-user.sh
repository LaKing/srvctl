#!/bin/bash

## @@@ add-user USERNAME
## @en Add user to the systems
## &en Add user to database and create it on the system.
## &en users will have default passwords, certificates, etc, ..

## if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
## SC_USE_containerfarm

sudomize
argument username

local username password reseller
username="${ARG,,}"

# shellcheck disable=SC2154
if $SC_USE_datastore
then
    
    if [[ "$(get user "$username" exist)" == true ]]
    then
        err "User $username already exist."
    else
        new user "$username"
        regenerate_users
    fi
    
    reseller="$(get user "$username" reseller)"
    
    if [[ $SC_USER == "$reseller" ]]
    then
        ntc "$username has reseller rights."
    else
        ntc "Reseller for $username is: $reseller"
    fi
    
else
    
    if id -u "$username" > /dev/null 2>&1
    then
        err "User $username already exist."
        return
    fi
    
    password="$(new_password)"
    ntc "Password for $username is: $password"
    
    adduser "$username"
    echo "$password" | passwd "$username" --stdin 2> /dev/null 1> /dev/null
    echo -e "$password" > "$(getent passwd "$username" | cut -f6 -d:)/.password"
    
fi


