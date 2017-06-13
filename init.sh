#!/bin/bash

# shellcheck disable=SC2034

[[ -f /etc/srvctl/debug.conf ]] && source /etc/srvctl/debug.conf

if [[ ! -d /etc/srvctl ]]
then
    mkdir -p /etc/srvctl
fi

## create startup symlinks for sc and srvctl commands
if [[ -f /usr/local/share/srvctl/srvctl.sh ]]
then
    if [[ ! -e /bin/sc ]]
    then
        sudo ln -s /usr/local/share/srvctl/srvctl.sh /bin/sc
    fi
    if [[ ! -e /bin/srvctl ]]
    then
        sudo ln -s /usr/local/share/srvctl/srvctl.sh /bin/srvctl
    fi
fi

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
    
    for sourcefile in /etc/srvctl/data/*.conf
    do
        [[ -f $sourcefile ]] && cat "$sourcefile" > /etc/srvctl/"${sourcefile:17}" && debug "@init data -> /etc/srvctl/${sourcefile:17}"
    done
fi

## LOAD CONFIGs
## source custom configurations

test_srvctl_modules
#source /etc/srvctl/modules.conf

for sourcefile in /etc/srvctl/*.conf
do
    debug "@conf $sourcefile"
    [[ -f $sourcefile ]] && source "$sourcefile"
done


debug "init@run_hook pre-init"
run_hook "pre-init-$CMD"
run_hook pre-init

source /etc/os-release

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
[[ ! $SC_ROOT == true ]] && SC_LOG_DIR=$SC_HOME/.srvctl/log


readonly CMD
readonly ARG
readonly ARGS
readonly OPA
readonly OPAS
readonly DEBUG

for dir in $SC_INSTALL_DIR/modules/*
do
    module="${dir##*/}"
    readonly "SC_USE_${module^^}"
done


export SC_USER
export SC_ROOT
export SRVCTL

## breakout to help-only
if [[ $CMD == "man" ]] || [[ $CMD == "help" ]] || [[ $CMD == "-help" ]] || [[ $CMD == "--help" ]]
then
    help_commands
    exit_0
fi

## load libs for running commands
debug "init@Load libs"
load_libs

## libs loaded, we can run the init hooks of modules
debug "init@run_hook init"
run_hook init

debug "init@run_hook post-init"
run_hook post-init
run_hook "post-init-$CMD"

