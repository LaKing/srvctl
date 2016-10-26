#!/bin/bash

## Lablib functions

## constants

readonly RED='\e[31m'
readonly GREEN='\e[32m'
readonly YELLOW='\e[33m'
readonly BLUE='\e[34m'
readonly GRAY='\e[37m'

# No Color
readonly CLEAR='\e[0m'


function msg {
    ## message for the user
    echo -e "${GREEN}$*${CLEAR}"
}

function ntc {
    ## notice for the user
    echo -e "${YELLOW}$*${CLEAR}"
}


function log {
    ## create a log entry
    echo -e "${YELLOW}$1${CLEAR}"
    echo "$NOW: $*" >> "$SC_LOG"
}

## silent log
function logs {
    ## create a log entry
    echo "$NOW: $*" >> "$SC_LOG"
}

function dbg {
    ## short debug message if debugging is on
    if $DEBUG
    then
        echo -e "${YELLOW}DEBUG ${BASH_SOURCE[1]}#${BASH_LINENO[1]} ${FUNCNAME[1]} :: $*${CLEAR}"
    fi
}
function debug {
    ## tracing debug message
    echo -e "${YELLOW}DEBUG ${BASH_SOURCE[1]}#${BASH_LINENO[1]} ${FUNCNAME[1]} :: $*${CLEAR}"
    set
    echo -e "${YELLOW}DEBUG ${BASH_SOURCE[1]}#${BASH_LINENO[1]} ${FUNCNAME[1]} :: $*${CLEAR}"
}
function err {
    ## error message
    echo -e "$NOW ERROR ${RED}$*${CLEAR}" >> "$SC_LOG"
    echo -e "${RED}$*${CLEAR}" >&2
}

function run {
    echo -e "${BLUE}$*${CLEAR}"
    # shellcheck disable=SC2048
    $*
}

## exit if failed
function exif {
    if [ "$?" != "0" ]
    then
        local exif_code="$?"
        ## the first in stack is what we are looking for. (0th is this function itself)
        err "EXIF ERROR $exif_code @ ${BASH_SOURCE[1]}#${BASH_LINENO[1]} ${FUNCNAME[1]} :: $*"
        exit 1;
    fi
}

## extra yell if failed
function eyif {
    if [ "$?" != "0" ]
    then
        err "EYIF ERROR $? @ ${BASH_SOURCE[1]}#${BASH_LINENO[1]} ${FUNCNAME[1]} :: $*"
    fi
}
