#!/bin/bash

readonly SC_INSTALL_BIN=$(realpath "$BASH_SOURCE")
readonly SC_INSTALL_DIR=${SC_INSTALL_BIN:0:-16}

readonly SC_ON_HS=true
readonly SC_ON_VE=true
readonly SC_USER=true
readonly SC_ROOT=true

## we use the format srvctl or sc command argument [plus-argument]
## command
readonly CMD=''
## argument
readonly ARG=''
## optional single argument
readonly OPA=''
## all arguments
readonly ARGS=''
## Current start directory

## Taken from LabLib ONLY for the manual
readonly GREEN='\e[32m'
readonly RED='\e[31m'
readonly BLUE='\e[34m'
readonly YELLOW='\e[33m'
readonly CLEAR='\e[0m' # No Color

function title {
    if [ ! -z "$1" ]
    then
        echo ''
        printf "${GREEN}"%-40s"${CLEAR}" "$1"
        echo ''
        echo ''
    fi
}

function hint {
    if [ ! -z "$1" ]
    then
        ## print formatted hint
        printf "${GREEN}"%-40s"${CLEAR}" "  $1"
        printf "${YELLOW}"%-48s"${CLEAR}" "$2"
        ## newline
        echo ''
        
    fi
}

function manual {
    printf "${YELLOW}"%-40s"${CLEAR}" "  $1"
    echo ''
    echo ''
}

function msg {
    echo '' > /dev/null
}

function helperr {
    ## help error message
    echo -e "${RED}$*${CLEAR}" >&2
}

function complicate {
    echo '' > /dev/null
}

title "Fedora-srvctl v3 by Istvan Kiraly - LaKing@D250.hu - D250 Laboratories - 2016"

source "$SC_INSTALL_DIR/libs/commonlib.sh"



if [ -z "$1" ]
then
    title "srvctl COMMAND [arguments]"
    title "COMMAND"
    load_commands
    title "CMS"
    load_cms
    exit
else
    if [ -f "$SC_INSTALL_DIR/commands/$1.sh" ]
    then
        title "srvctl COMMAND [arguments]"
        title "COMMAND $1"
        source "$SC_INSTALL_DIR/commands/$1.sh"
        exit
    fi
fi

helperr "No help for $1"

exit


