#!/bin/bash

##
##   lablib.sh — low-level output, logging and error helpers for srvctl.
##
##   Sourced by init.sh before commonlib.sh; every function here may be
##   used by any module script. No srvctl state is required except the
##   variables noted per function (SC_LOG, NOW, DEBUG, SC_TTY, SRVCTL).
##
##   Color/output contract (do not change formats — parsed downstream):
##     msg/ntc/err print "[ shorthostname ] text" (blue prefix),
##     err additionally logs to $SC_LOG and writes to stderr.
##

## color constants for use everywhere
readonly RED='\e[31m'
readonly GREEN='\e[32m'
readonly YELLOW='\e[33m'
readonly BLUE='\e[34m'
readonly GRAY='\e[37m'
readonly CLEAR='\e[0m'

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
    echo "$NOW [ $SC_USER@${HOSTNAME%%.*} ]: $*" >> "$SC_LOG"
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
    if $DEBUG && $SC_TTY
    then
        # shellcheck disable=SC2128
        echo -e "${YELLOW}DEBUG #$dbgc ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} ${GREEN} $* ${CLEAR}"
    fi
}
function debug {
    ## short debug message if debugging is on
    local now
    if $DEBUG && $SC_TTY
    then
        now="$(date +%s%3N)"
        echo -e "${GREEN}# $((now-SC_STARTTIME))${YELLOW} $* ${CLEAR}"
    fi
}

function trace {
    ## tracing debug message
    # shellcheck disable=SC2128
    echo -e "${YELLOW} DEBUG ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} ${RED} $*${CLEAR}"
    set -o posix;
    set | grep BASH_LINENO=
    set | grep BASH_SOURCE=
    set | grep FUNCNAME=
    set | grep SC_
    # shellcheck disable=SC2128
    echo -e "${YELLOW} DEBUG ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} ${RED} $*${CLEAR}"
}
function err {
    ## error message
    echo -e "$USER@$HOSTNAME $NOW ERROR ${RED}$*${CLEAR}" >> "$SC_LOG"
    echo -e "${BLUE}[ ${HOSTNAME%%.*} ] ${RED}$*${CLEAR}" >&2
}

## Fill FILE with the stdout of a command, for generated files that a daemon
## or the resolver reads. 'cmd > FILE' empties the file before cmd has printed
## anything and leaves it empty when cmd fails (an empty /etc/hosts, an empty
## postfix relay map). Here the output goes to a temporary file beside FILE and
## replaces it by rename, only when the command succeeded and printed
## something; an unchanged FILE is not touched. FILE keeps its mode, owner and
## SELinux label. Not for output that may legitimately be empty.
function write_output { ## FILE COMMAND [ARG...]
    local file="$1" tmp rc
    shift
    tmp="$(mktemp "$file.XXXXXX")" || return 1
    "$@" > "$tmp"
    rc=$?
    if [[ $rc != 0 ]] || [[ ! -s $tmp ]]
    then
        rm -f "$tmp"
        err "$file is left as it was: '$*' failed (exit $rc) or printed nothing"
        return 1
    fi
    if [[ -f $file ]] && cmp -s "$tmp" "$file"
    then
        rm -f "$tmp"
        return 0
    fi
    if [[ -e $file ]]
    then
        chmod --reference="$file" "$tmp"
        chown --reference="$file" "$tmp"
        chcon --reference="$file" "$tmp" 2> /dev/null
    else
        chmod 644 "$tmp"
    fi
    mv -f "$tmp" "$file"
}

## TEST SEAM for the selftests, not supported configuration.
: "${SC_MOUNTINFO:=/proc/self/mountinfo}"

## Print every mount point at or below DIR, deepest first.
function mounts_in { ## DIR
    awk -v dir="$1" '$5 == dir || index($5, dir "/") == 1 { print $5 }' "$SC_MOUNTINFO" | sort -r
}

## Remove leftovers: paths srvctl once created on this host that nothing owns
## any more (a removed container's unit link, a removed module's files). The
## modules call this from their prune hook; the caller decides WHAT is a
## leftover, this function only removes it safely:
## - every removal is announced and written to the log;
## - a path with a mount at or below it is refused, because 'rm -r' through a
##   live mount deletes the mounted data (a user's share, a comount);
## - a path shallower than /a/b, or holding '..', is refused;
## - with SC_PRUNE_DRY_RUN=true nothing is removed, the leftovers are listed.
function prune { ## PATH...
    local path
    for path in "$@"
    do
        [[ -e $path || -L $path ]] || continue
        if [[ $path != /*/* ]] || [[ $path == */ ]] || [[ $path == *..* ]]
        then
            err "Refusing to prune '$path'"
            continue
        fi
        if [[ ! -L $path ]] && [[ -n $(mounts_in "$path") ]]
        then
            err "Leftover $path is not removed: something is mounted in it"
            continue
        fi
        if [[ ${SC_PRUNE_DRY_RUN:-false} == true ]]
        then
            ntc "Leftover (dry run, not removed): $path"
            continue
        fi
        ntc "Removing leftover $path"
        logs "prune $path"
        rm -rf --one-file-system -- "$path"
    done
}

## echo a shell-prompt-style line, then execute the arguments as a command.
## Returns the command's exit code. Word-splitting of $* is intentional
## (callers pass whole command lines); arguments with spaces cannot be used.
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

    ## FIXME(v4): this warning can never print — eyif is called from the
    ## then-branch, so it captures $? of the just-evaluated [[ ]] condition
    ## (always 0) instead of $__exitcode. The exemption logic is also
    ## inverted (intended: don't warn for 'systemctl * status' returning 3).
    ## Kept as-is: fixing it would surface new warnings in many commands.
    if [[ $1 != systemctl ]] && [[ $2 != status ]] && [[ $__exitcode != 3 ]]
    then
        eyif "command '$*' returned with an error $__exitcode"
    fi

    return $__exitcode
}

## a kind of run, but without running anything — prints the prompt-style
## line only. Used to show a command to the user instead of executing it.
function nur {
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


## exit if failed — call directly after a command; exits the whole CLI with
## that command's exact code, printing $* (or a located error in DEBUG mode).
function exif {
    local exif_code="$?"
    if [ "$exif_code" != "0" ]
    then
        if $DEBUG
        then
            ## the first in stack is what we are looking for. (0th is this function itself)
            # shellcheck disable=SC2128
            err "ERROR $exif_code @ ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} :: $*"
        else
            err "$*"
        fi
        exit "$exif_code";
    fi
}

## extra yell if failed — like exif but only warns; returns the original code.
function eyif {
    local eyif_code="$?"
    if [ "$eyif_code" != "0" ]
    then
        if $DEBUG
        then
            # shellcheck disable=SC2128
            err "ERROR $eyif_code @ ${BASH_SOURCE[1]}#$BASH_LINENO ${FUNCNAME[1]} :: $*"
        else
            err "$*" "$eyif_code"
        fi
    fi
    return "$eyif_code"
}

function exit_0() {
    ## exit normally, without error, printing the "## srvctl-x.y.z.w" trailer.
    ## The trailer is suppressed for exec-function on purpose: machine
    ## consumers (lablib.js exec_function) parse that output.
    if $DEBUG && $SC_TTY
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

