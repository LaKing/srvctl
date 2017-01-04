#!/bin/bash

if $IS_ROOT && $ON_HS
then
    msg "-- user database --"
    cat /etc/srvctl/users.json
    msg "-- container database --"
    cat /etc/srvctl/containers.json
fi
