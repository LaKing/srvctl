#!/bin/bash

## lablib is mainly for colorization
source "$SC_INSTALL_DIR/lablib.sh" || echo "lablib could not be loaded!" 1>&2

## init main lib
source "$SC_INSTALL_DIR/commonlib.sh" || echo "commonlib could not be loaded!" 1>&2

## logging related
readonly NOW=$(date +%Y.%m.%d-%H:%M:%S)

run_hooks pre-init

source /etc/os-release

## LOAD CONFIG

## source the default values
source "$SC_INSTALL_DIR/config" || echo "Default-config could not be loaded!" 1>&2

## source custom configurations
if [[ -f /etc/srvctl/config ]]
then
    source /etc/srvctl/config
fi

# shellcheck disable=SC2034
SC_LOG_DIR=/var/log/srvctl

if [[ $USER == root ]] && [[ -z $SUDO_USER ]]
then
    readonly SC_ROOT=true
    readonly SC_USER="$SC_ROOT_USERNAME"
    readonly SC_HOME=~root
else
    if [[ -z $SUDO_USER ]]
    then
        readonly SC_USER="$USER"
        readonly SC_HOME=~
    else
        readonly SC_USER="$SUDO_USER"
        readonly SC_HOME=~$SC_USER
    fi
    readonly SC_ROOT=false
fi

readonly CMD="${CMD,,}"
readonly ARG
readonly ARGS
readonly OPA
readonly OPAS
readonly DEBUG

run_hooks post-init

## breakout to help-only
if [[ $CMD == "man" ]] || [[ $CMD == "help" ]] || [[ $CMD == "-help" ]] || [[ $CMD == "--help" ]]
then
    help_commands
    exit
fi
