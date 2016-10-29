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
