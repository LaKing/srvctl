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
    ## debug message
    if $DEBUG
    then
        echo -e "${YELLOW}#$BASH_LINENO ${FUNCNAME[1]}: $*${CLEAR}"
    fi
    echo "$NOW ${FUNCNAME[1]} $*" >> "$SC_LOG"
}

function err {
    ## error message
    echo -e "$NOW ERROR ${RED}$*${CLEAR}" >> "$SC_LOG"
    echo -e "${RED}$*${CLEAR}" >&2
}

function run {
    echo -e "${BLUE}$*${CLEAR}"
    "$*"
}

## exit if failed
function exif {
    if [ "$?" != "0" ]
    then
        err "Error. #$BASH_LINENO ${FUNCNAME[1]} returned with a failure"
        exit 1;
    fi
}

## extra yell if failed
function eyif {
    if [ "$?" != "0" ]
    then
        err "Error. #$BASH_LINENO ${FUNCNAME[1]} returned with a failure"
    fi
}
