#!/bin/bash

###
###   srvctl v3 with systemd-containers intended to use on fedora 25 and later
###
###   D250 Laboratories / D250.hu
###   Author: István király
###   LaKing@D250.hu
###

###
###  trying to be compatible with
###  https://google.github.io/styleguide/shell.xml
###
###  But please, then, do, etc on seperate lines. Better readble.
###

## can be set true in /etc/srvctl/config
# shellcheck disable=SC2034
DEBUG=false

readonly SC_INSTALL_BIN=$(realpath "$BASH_SOURCE")
readonly SC_INSTALL_DIR=${SC_INSTALL_BIN:0:-10}

## command arguments saved into variables
# shellcheck disable=SC2034
CMD="$1"
# shellcheck disable=SC2034
CMD="${CMD,,}"
# shellcheck disable=SC2034
ARG="$2"
# shellcheck disable=SC2034
ARGS="$*"
# shellcheck disable=SC2034
OPA="$3"
# shellcheck disable=SC2034
# shellcheck disable=SC2124
OPAS="${@:2}"

source "$SC_INSTALL_DIR/init.sh" || echo "Init could not be loaded!" 1>&2

## load libs for running commands
load_libs

run_command

if [ "$?" == 0 ]
then
    msg "srvctl v3 ready"
else
    ## something gone wrong, or user did something bad
    
    ## check for arguments
    if [ -z "$CMD" ]
    then
        err "No command."
    else
        err "Invalid Command."
        echo ''
    fi
    
    hint_commands
fi



