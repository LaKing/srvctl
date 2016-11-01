#!/bin/bash

function root_only {
    if $SC_ROOT
    then
        return 0
    else
        err "Authorization failure"
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

function authorize {
    
    if ! $SC_ROOT
    then
        ## authorize SC_USER
        
        ## ...
        dbg auth
    fi
}

