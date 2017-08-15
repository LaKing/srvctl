#!/bin/bash

function hs_only {
    if $SC_ON_HS
    then
        return 0
    else
        err "Authorization failure - this command is host-only"
        exit 44
    fi
}

function ve_only {
    if $SC_ON_VE
    then
        return 0
    else
        err "Authorization failure - this command is VE-only"
        exit 44
    fi
}
