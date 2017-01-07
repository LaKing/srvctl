#!/bin/bash

# shellcheck disable=SC2034
DEBUG=false
[[ -f /etc/srvctl/debug.conf ]] && source /etc/srvctl/debug.conf

## lablib is mainly for colorization
source "$SC_INSTALL_DIR/lablib.sh" || echo "lablib could not be loaded!" 1>&2

## init main lib
source "$SC_INSTALL_DIR/commonlib.sh" || echo "commonlib could not be loaded!" 1>&2

## logging related
readonly NOW=$(date +%Y.%m.%d-%H:%M:%S)
export NOW

# shellcheck disable=SC2034
SC_LOG_DIR=~
# shellcheck disable=SC2034
SC_LOG=~/.srvctl.log

if [[ $CMD == update-install ]]
then
    rm -fr /etc/srvctl/modules.conf
fi

test_srvctl_modules
source /etc/srvctl/modules.conf

run_hooks "pre-init-$CMD"
run_hooks pre-init

source /etc/os-release

## LOAD CONFIGs
## source custom configurations

for sourcefile in /etc/srvctl/*.conf
do
    [[ $DEBUG == true ]] && ntc "@conf $sourcefile"
    [[ -f $sourcefile ]] && source "$sourcefile"
done

## homedir=$( getent passwd "$USER" | cut -d: -f6 )


if [[ $USER == root ]] && [[ -z $SUDO_USER ]]
then
    readonly SC_ROOT=true
    readonly SC_USER="$SC_ROOT_USERNAME"
else
    if [[ -z $SUDO_USER ]]
    then
        readonly SC_USER="$USER"
    else
        readonly SC_USER="$SUDO_USER"
    fi
    readonly SC_ROOT=false
fi

readonly SC_HOME="$(getent passwd "$SC_USER" | cut -f6 -d:)"

# shellcheck disable=SC2034
[[ ! $SC_ROOT == true ]] && SC_LOG_DIR=$SC_HOME/.srvct/log


readonly CMD
readonly ARG
readonly ARGS
readonly OPA
readonly OPAS
readonly DEBUG

for dir in $SC_INSTALL_DIR/modules/*
do
    readonly "SC_USE_${dir##*/}"
done


export SC_USER
export SC_ROOT
export SRVCTL

## breakout to help-only
if [[ $CMD == "man" ]] || [[ $CMD == "help" ]] || [[ $CMD == "-help" ]] || [[ $CMD == "--help" ]]
then
    help_commands
    exit
fi

## load libs for running commands
[[ $DEBUG == true ]] && ntc "@Load libs"
load_libs

run_hooks post-init
run_hooks "post-init-$CMD"

