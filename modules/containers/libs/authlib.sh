#!/bin/bash

function hs_only {
    if [[ $SC_HOSTNET ]]
    then
        return 0
    else
        err "Authorization failure - this command is host-only"
        exit 44
    fi
}

function ve_only {
    if $SC_USE_VE
    then
        return 0
    else
        err "Authorization failure - this command is VE-only"
        exit 44
    fi
}
