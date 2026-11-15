#!/bin/bash

##
##   containers/libs/prunelib.sh — remove what removed containers left behind.
##
##   run_prune is what 'sc regenerate', remove-ve and destroy-ve call: it reads
##   the container records once and runs the prune hook of every module. The
##   hooks ask container_is_gone, so every module uses the same test:
##
##   A container is gone only when it has NO record in the datastore AND NO
##   directory in /srv. Either one alone keeps its artifacts: a failed
##   datastore read must not make every container look removed, and a
##   directory without a record is imported by check_container_directories.
##
##   Outside /srv/C this module itself keeps three things per container, all
##   derived from the datastore: the link that starts the unit at boot, the
##   unit's drop-in directory (resource limits, comount) and the share
##   directory that is bind-mounted into the container (copies of user keys
##   and password hashes).
##

## TEST SEAMS for the selftest, not supported configuration.
: "${SC_PRUNE_UNIT_DIR:=/etc/systemd/system}"
: "${SC_PRUNE_SHARE_DIR:=/var/srvctl3/share/containers}"
: "${SC_PRUNE_SRV_DIR:=/srv}"

## The registered container names between spaces; empty outside run_prune and
## when the datastore could not be read, and then no container counts as gone.
SC_PRUNE_CONTAINERS=""

function run_prune {
    local rows

    ## list reports its own failure
    SC_PRUNE_CONTAINERS=""
    if rows="$(list container)"
    then
        SC_PRUNE_CONTAINERS=" ${rows//$'\n'/ } "
    fi

    run_hook prune
    SC_PRUNE_CONTAINERS=""
}

function container_is_gone { ## C
    [[ -n $SC_PRUNE_CONTAINERS ]] && [[ $SC_PRUNE_CONTAINERS != *" $1 "* ]] && [[ ! -e $SC_PRUNE_SRV_DIR/$1 ]]
}

function prune_container_leftovers {
    local path C unit reload=false

    for path in "$SC_PRUNE_UNIT_DIR"/machines.target.wants/srvctl-nspawn@*.service \
        "$SC_PRUNE_UNIT_DIR"/srvctl-nspawn@*.service.d \
        "$SC_PRUNE_SHARE_DIR"/*
    do
        [[ -e $path || -L $path ]] || continue
        C="${path##*/}"
        C="${C#srvctl-nspawn@}"
        C="${C%.service.d}"
        C="${C%.service}"
        container_is_gone "$C" || continue
        prune "$path"
        [[ $path == "$SC_PRUNE_SHARE_DIR"/* ]] || reload=true
    done

    [[ ${SC_PRUNE_DRY_RUN:-false} != true ]] || return 0
    $reload && systemctl daemon-reload

    ## A removed container's unit stays listed as failed until the next boot.
    while read -r -u 3 unit _
    do
        C="${unit#srvctl-nspawn@}"
        C="${C%.service}"
        container_is_gone "$C" || continue
        ntc "Clearing the failed state of $unit"
        systemctl reset-failed "$unit"
    done 3< <(systemctl list-units 'srvctl-nspawn@*' --state=failed --plain --no-legend)
}
