#!/bin/bash

## constants for use everywhere
readonly RED='\e[31m'
readonly GREEN='\e[32m'
readonly YELLOW='\e[33m'
readonly BLUE='\e[34m'
readonly GRAY='\e[37m'

## Lablib functions

function prg {
    ## print green
    echo -e "${GREEN}$*${CLEAR}"
}

function pry {
    ## print yellow
    echo -e "${YELLOW}$*${CLEAR}"
}

function msg {
    ## message for the user
    echo -e "${BLUE}[ ${HOSTNAME%%.*} ] ${GREEN}$*${CLEAR}"
}

function ntc {
    ## notice for the user
    echo -e "${BLUE}[ ${HOSTNAME%%.*} ] ${YELLOW}$*${CLEAR}"
}


function log {
    ## create a log entry
    echo -e "${BLUE}[ ${HOSTNAME%%.*} ] ${YELLOW}$1${CLEAR}"
    echo "$NOW: $*" >> "$SC_LOG"
}

## silent log
function logs {
    ## create a log entry
    echo "$NOW: $*" >> "$SC_LOG"
}

## silent log a file content
function logfs {
    ## create a log entry
    echo "$NOW: cat $*" >> "$SC_LOG"
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    cat $* >> "$SC_LOG"
}

dbgc=0
function dbg {
    ((dbgc++))
    ## short debug message if debugging is on
    if $DEBUG && $TTY
    then
        echo -e "${YELLOW}DEBUG #$dbgc ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} ${GREEN} $* ${CLEAR}"
    fi
}
function debug {
    ## short debug message if debugging is on
    local now
    if $DEBUG && $TTY
    then
        now="$(date +%s%3N)"
        echo -e "${GREEN}# $((now-SC_STARTTIME))${YELLOW} $* ${CLEAR}"
    fi
}

function trace {
    ## tracing debug message
    echo -e "${YELLOW} DEBUG ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} ${RED} $*${CLEAR}"
    set -o posix;
    set | grep BASH_LINENO=
    set | grep BASH_SOURCE=
    set | grep FUNCNAME=
    set | grep SC_
    echo -e "${YELLOW} DEBUG ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} ${RED} $*${CLEAR}"
}
function err {
    ## error message
    echo -e "$USER@$HOSTNAME $NOW ERROR ${RED}$*${CLEAR}" >> "$SC_LOG"
    echo -e "${BLUE}[ ${HOSTNAME%%.*} ] ${RED}$*${CLEAR}" >&2
}

function run {
    local signum='$'
    local __exitcode
    if [ "$USER" == root ]
    then
        signum='#'
    fi
    local WDIR
    WDIR="$(basename "$PWD")"
    echo -e "${BLUE}[$USER@${HOSTNAME%%.*} ${WDIR/#$HOME/\~}]$signum ${YELLOW}$*${CLEAR}"
    
    # shellcheck disable=SC2048
    $*
    __exitcode=$?
    
    if [[ $1 != systemctl ]] && [[ $2 != status ]] && [[ $__exitcode != 3 ]]
    then
        eyif "command '$*' returned with an error $__exitcode"
    fi
    
    return $__exitcode
}

## a kind of run, but without running anything
function say {
    local signum='$'
    local __exitcode
    if [ "$USER" == root ]
    then
        signum='#'
    fi
    local WDIR
    WDIR="$(basename "$PWD")"
    echo -e "${BLUE}[$USER@${HOSTNAME%%.*} ${WDIR/#$HOME/\~}]$signum ${YELLOW}$*${CLEAR}"
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
            err "$*" "$eyif_code"
        fi
    fi
    return "$eyif_code"
}

function exit_0() {
    
    if $DEBUG && $TTY
    then
        debug "$SRVCTL"
        exit 0
    fi
    
    [[ $CMD != "exec-function" ]] &&  msg "## $SRVCTL"
    exit 0
}

function sed_file {
    ## used to replace a line in a file
    ## filename=$1 oldline=$2 newline=$3
    cat "$1" > "$1.tmp"
    sed "s|$2|$3|" "$1.tmp" > "$1"
    rm "$1.tmp"
}

function add_conf {
    ## check if the content string is present, and add if necessery. Single-line content only.
    ## filename=$1 content=$2
    if [ -f "$1" ]
    then
        if ! grep -q "$2" "$1"
        then
            echo "$2" >> "$1"
        fi
    else
        err "File not found! $1 (add_conf)"
    fi
}

