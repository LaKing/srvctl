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

if tty > /dev/null
then
    ## in terminal
    TTY=true
else
    ## in srvctl-gui
    TTY=false
fi

if [[ $USER == root ]]
then
    ## okay THIS IS REALLY only for development.
    [[ -f /bin/pop ]] && "$TTY" && sudo /bin/pop
fi

## can be set true in /etc/srvctl/config
# shellcheck disable=SC2034
DEBUG=false
# shellcheck disable=SC2034
#[[ -f /bin/pop ]] && DEBUG=true

readonly SC_STARTTIME="$(date +%s%3N)"

readonly SC_INSTALL_BIN=$(realpath "$BASH_SOURCE")
readonly SC_INSTALL_DIR=${SC_INSTALL_BIN:0:-10}
readonly SC_COMMAND_ARGUMENTS="$*"

## should be /usr/local/share/srvctl
export SC_INSTALL_DIR

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

[ "$CMD" == "?" ] && CMD=status
[ "$CMD" == "+" ] && CMD=start
[ "$CMD" == "-" ] && CMD=stop
[ "$CMD" == "!" ] && CMD=restart

[ "$ARG" == "?" ] && ARG=status
[ "$ARG" == "+" ] && ARG=start
[ "$ARG" == "-" ] && ARG=stop
[ "$ARG" == "!" ] && ARG=restart

## Check against the existance of the variable, and use it as base dir in var, eg /var/$SRVCTL/something
SRVCTL="srvctl-$(cat "$SC_INSTALL_DIR/version")"
readonly SRVCTL


source "$SC_INSTALL_DIR/init.sh" || echo "Init could not be loaded!" 1>&2

if [[ ! -f /var/local/srvctl/commands.spec ]]
then
    make_commands_spec
fi

debug " == run_command srvctl $CMD $ARG == "
run_command

if [[ $? == 0 ]]
then
    exit_0
fi

## something gone wrong, or user did something bad

## check for arguments
if [[ $CMD ]]
then
    err "Invalid command."
else
    err "No-command."
fi

hint_commands

exit 1

