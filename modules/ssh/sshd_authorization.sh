#!/bin/bash

_user="$1"

function catif() {
    if [[ -f $1 ]]
    then
        cat "$1"
    fi
}

## used by root as root
catif "/etc/srvctl/authorized_keys"

## used on the host, for host-to-host authentication
catif "/var/srvctl3/datastore/rw/users/$_user/authorized_keys"

## used in containers for user as root
catif "/var/srvctl3/share/containers/$HOSTNAME"/users/*/authorized_keys
