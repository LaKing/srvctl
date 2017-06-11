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

function argument {
    if [[ -z $ARG ]]
    then
        err "Argument $1 missing."
        exit 32
    fi
}

function authorize {
    if $SC_ROOT
    then
        return
    else
        err "Authorization implementation not complete"
    fi
}

function sudomize {
    if [[ $USER != root ]]
    then
        if ! run sudo "$SC_INSTALL_DIR/srvctl.sh" "$SC_COMMAND_ARGUMENTS"
        then
            err "Could not use sudo."
        fi
        exit
    fi
}





