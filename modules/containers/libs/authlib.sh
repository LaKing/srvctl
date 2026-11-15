#!/bin/bash

##
##   containers/libs/authlib.sh — container checks for the command files.
##   The identity guards are in modules/srvctl/libs/authlib.sh.
##

## End the command with 22 unless container C has a record. Called before
## owner_only, which would report a missing record as a failed lookup.
function existing_container { ## C
    local exists
    exists="$(get container "$1" exist)" || exit $?
    [[ $exists == true ]] && return 0
    err "No such container: $1"
    exit 22
}
