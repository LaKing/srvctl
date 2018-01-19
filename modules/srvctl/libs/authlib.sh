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

function reseller_only {
    if [[ "${#SC_USER}" == 1 ]] || $SC_ROOT
    then
        return 0
    else
        err "Resellers only."
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
        err "DEV (Authorization implementation not complete.)"
    fi
}

function sudomize {
    if [[ $USER != root ]]
    then
        debug "@sudomize"
        if ! run sudo "$SC_INSTALL_DIR/srvctl.sh" "$SC_COMMAND_ARGUMENTS"
        then
            debug "Error $? in srvctl-sudo"
            exit 10
        else
            exit 0
        fi
    fi
}




