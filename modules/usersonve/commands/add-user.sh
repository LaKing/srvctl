#!/bin/bash

## @@@ add-user USERNAME
## @en Add user to the container
## &en Add user to the container, so that they have their own files, email accouns, and so on.
## &en users will have a default password, and a directory structure in the container home.

argument username

local username password
username="${ARG,,}"

if ! [[ "$username" =~ ([a-z_][a-z0-9_]{2,30}) ]]
then
    err "Invalid username: $username"
    exit 22
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
