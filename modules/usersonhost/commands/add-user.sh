#!/bin/bash

## @@@ add-user USERNAME
## @en Add user to the current cluster
## &en Create the user in the current cluster datastore and create it on the system.
## &en users will have default passwords, certificates, etc, ..

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument username
operators_only
sudomize

##
##   Registers USERNAME in the cluster datastore (new user) and runs
##   regenerate_users (main.js): system account, password, ssh keys, client
##   certificate and container share mounts. A user is an account on the
##   host, so creating one is for root and operators.
##

## sourced by run_command, so this runs in a function scope
## the datastore key is the lowercased argument
username="${ARG,,}"

## anchored: =~ matches a substring, and the value flows into the datastore key and adduser
## FIXME(v4): share one validator with the other add-*user commands
if ! [[ "$username" =~ ^[a-z_][a-z0-9_]{2,30}$ ]]
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

fi
