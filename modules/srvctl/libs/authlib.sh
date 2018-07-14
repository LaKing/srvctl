#!/bin/bash

function root_only {
    if [[ $SC_USER == root ]]
    then
        return 0
    else
        err "Authorization failure. (root_only)"
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
        ## there should be several levels of users
        ## root - allowed everything for everyone
        ## reseller - allowed for his users
        ## user - allowed for himself
        ## guest - limited.
        err "DEV (Authorization implementation not complete.)"
    fi
}

function sudomize {
    if ! $SC_ROOT
    then
        debug "@sudomize"
        if run sudo "$SC_INSTALL_DIR/srvctl.sh" "$SC_COMMAND_ARGUMENTS"
        then
            exit
        else
            debug "Error $? in srvctl-sudo"
            exit $?
        fi
    fi
}




