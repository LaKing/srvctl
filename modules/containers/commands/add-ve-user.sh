#!/bin/bash

## @@@ add-ve-user VE USERNAME
## @en Give a user access to a container
## &en USERNAME gets ssh access to VE and its files in his home on the host.
## &en The owner of VE can add existing users; a new user is created by an operator.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container-name
existing_container "$ARG"
owner_only container "$ARG"

##
##   containers/commands/add-ve-user.sh — append USERNAME to the users list
##   of container VE; the regenerate hooks then make the access real (ssh
##   keys in the container, the share in the user's home). A USERNAME without
##   a record is created first, which only root and operators may do: a new
##   user is a new account on the host.
##

C="$ARG"
username="${OPA,,}"

## anchored: =~ matches a substring, so without ^...$ any name containing one valid run would pass
if ! [[ "$username" =~ ^([a-z]|[a-z_][a-z0-9_]{2,30})$ ]]
then
    err "Invalid username: $username"
    exit 22
fi

if [[ "$(get user "$username" exist)" != true ]]
then
    ## not written as a guard call: this command is the owner's, and the help
    ## would hide it from users if it carried the operators' marker
    if [[ $(sc_role) == user ]]
    then
        err "No such user: $username. An operator creates users with add-user."
        exit 44
    fi
    new user "$username"
    regenerate_users
fi

add container "$C" user "$username"

run_hook regenerate
