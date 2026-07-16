#!/bin/bash

###
###   srvctl v4 with systemd-containers intended to use on fedora 40 and later
###
###   D250 Laboratories / D250.hu
###   Author: István király
###   LaKing@D250.hu
###
###   Entry point (installed as /bin/sc and /bin/srvctl).
###   Collects the module list into SC_MODULES (root custom modules from
###   /root/srvctl-includes/modules first, then the installed modules/),
###   parses the command line into CMD/ARG/ARGS/OPA/OPAS, sources init.sh
###   (config + hooks), and dispatches via run_command (commonlib.sh).
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
    ## Dev-box auto-resync: when /bin/pop exists, EVERY root TTY invocation
    ## runs it before dispatch. Never present on production installs.
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
## strip the trailing "/srvctl.sh" (10 chars) to get the install dir
readonly SC_INSTALL_DIR="${SC_INSTALL_BIN:0:-10}"
readonly SC_COMMAND_ARGUMENTS="$*"
## Original argv preserved as an array so sudomize (modules/srvctl/libs/
## authlib.sh) can re-exec through sudo without collapsing arguments that
## contain spaces. Consumed cross-file.
# shellcheck disable=SC2034
SC_ARGV=("$@")

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

## bugfix(v4-polish): abort hard when init fails — continuing without init
## used to cascade into "command not found" noise before exiting 1 anyway.
# shellcheck source=/usr/local/share/srvctl/init.sh
source "$SC_INSTALL_DIR/init.sh" || { echo "Init could not be loaded!" 1>&2; exit 1; }
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
    err "Invalid command. $CMD"
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

