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

DEBUG=false

readonly SC_INSTALL_BIN=$(realpath "$BASH_SOURCE")
readonly SC_INSTALL_DIR=${SC_INSTALL_BIN:0:-9}

## logging related
readonly NOW=$(date +%Y.%m.%d-%H:%M:%S)

## detect virtualization
readonly SC_VIRT=$(systemd-detect-virt -c)

## lxc is deprecated, but we can consider it a container ofc.
if [[ "$SC_VIRT" == systemd-nspawn ]] || [[ "$SC_VIRT" == lxc ]]
then
    export SC_ON_VE=true
else
    export SC_ON_VE=false
fi

SC_ON_HS=false

## command arguments should be saved into variables
CMD="$1"
readonly CMD="${CMD,,}"
## argument
readonly ARG="$2"
readonly ARGS="$*"
readonly OPA="$3"

## breakout to help-only
if [ "$CMD" == "man" ] || [ "$CMD" == "help" ] || [ "$CMD" == "-help" ] || [ "$CMD" == "--help" ]
then
    /bin/bash "$SC_INSTALL_DIR/srvctl-manual.sh" "$ARG"
    exit
fi

source /etc/os-release

## TODO authorize here

readonly SC_ROOT=true

SC_CMD_OK=false
SC_COMMAND_LIST='help'

## hint and manual provides a sort of help functionality - initialize empty
function hint {
    echo 0 >> /dev/null
}

## the complication is to add to autocomplete
function complicate {
    SC_COMMAND_LIST="$SC_COMMAND_LIST $*"
}

function man_en {
    echo 0 >> /dev/null
}

## this is used at the end of command-blocks, to confirm command success or failure.
function ok {
    SC_CMD_OK=true
}


readonly SC_LOG_DIR="/var/log/srvctl"
readonly SC_LOG="$SC_LOG_DIR/srvctl.log"

SC_COMPANY=$HOSTNAME
SC_COMPANY_DOMAIN=$HOSTNAME
SC_HOSTNET=0

## source the default values
source "$SC_INSTALL_DIR/config" || err "Default configs could not be loaded!"

## source custom configurations
if [ -f /etc/srvctl/config ]
then
    source /etc/srvctl/config
fi

mkdir -p $SC_LOG_DIR

readonly SC_LOG_DIR
readonly SC_HOSTNET
readonly SC_COMPANY
readonly SC_COMPANY_DOMAIN

readonly DEBUG

## platform dependent commands



if  [[ "$SC_HOSTNET" -gt 10 ]] && [[ "$SC_HOSTNET" -lt 250 ]]
then
    
    export SC_ON_HS=true
fi

## FINALIZE

## init libs
source "$SC_INSTALL_DIR/commonlib.sh"
load_libs

#load the commands - and execute them
load_commands

## check if command completion works and save loaded command completion words
if [ ! -f "$SC_COMMAND_COMPLETION_DEFINITIONS" ] || $DEBUG
then
    update_command_completion
fi

function hint {
    if [ ! -z "$1" ]
    then
        ## print formatted hint
        printf "${GREEN}%-40s${CLEAR}" "   $1"
        printf "${YELLOW}%-48s${CLEAR}" " $2"
        ## newline
        echo ''
    fi
}

### thats it. Display help or succes info.
if "$SC_CMD_OK"
then
    msg "srvctl v3 ready"
else
    ## check for arguments
    if [ -z "$CMD" ]
    then
        err "No command."
    else
        err "Invalid Command."
        echo ''
    fi
    
    msg "Usage: srvctl command [argument]"
    msg "list of currently active commands:"
    
    
    hint_commands
    ## print formatted hint about man
    printf "${GREEN}%-40s${CLEAR}" "   help"
    printf "${YELLOW}%-48s${CLEAR}" " see more detailed descriptions about commands."
    ## newline
    echo ''
    echo ''
    
    if $IS_ROOT && $SC_ON_VE
    then
        msg "CMS list:"
        hint_cms
        echo ''
    fi
    
fi



