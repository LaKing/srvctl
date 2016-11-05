#!/bin/bash

function root_only {
    if $SC_ROOT
    then
        return 0
    else
        err "Authorization failure - this is root-only"
        exit 44
    fi
}

function sudomize {
    if ! $SC_ROOT
    then
        if ! sudo "$*"
        then
            err "Could not use sudo."
        fi
        exit
    fi
}



