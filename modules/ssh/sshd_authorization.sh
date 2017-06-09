#!/bin/bash

local _user

_user=$1

function catif() {
    local _file
    _file=$1
    if [[ -f $_file ]]
    then
        cat $_file
    fi
}

## used on the host, for host-to-host authentication
catif "/var/srvctl3/datastore/rw/users/$_user/authorized_keys"

## used by root as root
catif "/etc/srvctl/authorized_keys"

## used in containers for users
catif "/etc/srvctl/users/$_user/authorized_keys"
