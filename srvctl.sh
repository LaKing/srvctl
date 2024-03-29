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
    SC_TTY=true
else
    ## in srvctl-gui, or in program
    SC_TTY=false
fi

if [[ $UID == 0 ]]
then
    ## okay THIS IS REALLY only for development.
    [[ -f /bin/pop ]] && "$SC_TTY" && /bin/pop
fi

## we met a situation in fedora 29 where hostname is undefined
if [[ $HOSTNAME ]]
then
    readonly HOSTNAME
else
    readonly HOSTNAME="$(uname -n)"
fi

## can be set true in /etc/srvctl/config
# shellcheck disable=SC2034
DEBUG=false
# shellcheck disable=SC2034
#[[ -f /bin/pop ]] && DEBUG=true

readonly SC_STARTTIME="$(date +%s%3N)"
# shellcheck disable=SC2128
readonly SC_INSTALL_BIN="$(realpath "$BASH_SOURCE")"
readonly SC_INSTALL_DIR="${SC_INSTALL_BIN:0:-10}"
readonly SC_COMMAND_ARGUMENTS="$*"

## should be /usr/local/share/srvctl
export SC_INSTALL_DIR

SC_MODULES=''


## root-defined custom modules
if [[ -d /root/srvctl-includes/modules ]]
then
    for dir in /root/srvctl-includes/modules/*
    do
        if [[ -d $dir ]]
        then
            SC_MODULES="$SC_MODULES $dir"
        fi
    done
fi

## standard modules
for dir in $SC_INSTALL_DIR/modules/*
do
    SC_MODULES="$SC_MODULES $dir"
done

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

# shellcheck source=/usr/local/share/srvctl/init.sh
source "$SC_INSTALL_DIR/init.sh" || echo "Init could not be loaded!" 1>&2
debug " => $1 $2 $3"
debug " == run_command srvctl $CMD $ARG == "

if run_command
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

if [[ $CMD == 'exec-function' ]]
then
    echo "SC_USER: $SC_USER, UID: $UID, SC_TTY: $SC_TTY, CMD: $CMD, OPAS: $OPAS, DEBUG: $DEBUG"
    exit 1
fi

hint_commands

exit 1

