#!/bin/bash

## constants for use everywhere
readonly RED='\e[31m'
readonly GREEN='\e[32m'
readonly YELLOW='\e[33m'
readonly BLUE='\e[34m'
readonly GRAY='\e[37m'

## Lablib functions

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
dbgc=0
function dbg {
    ((dbgc++))
    ## short debug message if debugging is on
    if $DEBUG
    then
        echo -e "${YELLOW}DEBUG #$dbgc ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} ${RED} $* ${CLEAR}"
    fi
}
function debug {
    ## tracing debug message
    echo -e "${YELLOW}DEBUG ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} ${RED} $*${CLEAR}"
    set -o posix;
    set | grep BASH_LINENO=
    set | grep BASH_SOURCE=
    set | grep FUNCNAME=
    set | grep SC_
    echo -e "${YELLOW}DEBUG ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} ${RED} $*${CLEAR}"
}
function err {
    ## error message
    echo -e "$NOW ERROR ${RED}$*${CLEAR}" >> "$SC_LOG"
    echo -e "${RED}$*${CLEAR}" >&2
}

function run {
    local signum='$'
    if [ "$USER" == root ]
    then
        signum='#'
    fi
    local WDIR
    WDIR="$(basename "$PWD")"
    echo -e "${BLUE}[$USER@${HOSTNAME%%.*} ${WDIR/#$HOME/\~}]$signum ${YELLOW}$*${CLEAR}"
    
    # shellcheck disable=SC2048
    $*
    eyif "run function failed to execute '$*'"
}

## exit if failed
function exif {
    local exif_code="$?"
    if [ "$exif_code" != "0" ]
    then
        if $DEBUG
        then
            ## the first in stack is what we are looking for. (0th is this function itself)
            err "ERROR $exif_code @ ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} :: $*"
        else
            err "$*"
        fi
        exit "$exif_code";
    fi
}

## extra yell if failed
function eyif {
    local eyif_code="$?"
    if [ "$eyif_code" != "0" ]
    then
        if $DEBUG
        then
            err "ERROR $eyif_code @ ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} :: $*"
        else
            err "$*"
        fi
    fi
}
