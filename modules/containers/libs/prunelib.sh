#!/bin/bash

##
##   containers/libs/prunelib.sh — remove what removed containers left behind.
##
##   Outside /srv/C this module keeps three things per container, all derived
##   from the datastore: the link that starts the unit at boot, the unit's
##   drop-in directory (resource limits, comount) and the share directory that
##   is bind-mounted into the container (copies of user keys and password
##   hashes). remove-ve and destroy-ve run the prune hook, so these go with the
##   container; the same hook in every regenerate removes what older versions,
##   a crash or a hand-made move left.
##
##   A container is gone only when it has NO record in the datastore AND NO
##   directory in /srv. Either one alone keeps its artifacts: a failed
##   datastore read must not make every container look removed, and a
##   directory without a record is imported by check_container_directories.
##

## TEST SEAMS for the selftest, not supported configuration.
: "${SC_PRUNE_UNIT_DIR:=/etc/systemd/system}"
: "${SC_PRUNE_SHARE_DIR:=/var/srvctl3/share/containers}"
: "${SC_PRUNE_SRV_DIR:=/srv}"

function prune_container_leftovers {
    local registered path C unit reload=false

    ## list reports its own failure; without the records nothing is pruned.
    registered="$(list container)" || return 0
    registered=" ${registered//$'\n'/ } "

    for path in "$SC_PRUNE_UNIT_DIR"/machines.target.wants/srvctl-nspawn@*.service \
        "$SC_PRUNE_UNIT_DIR"/srvctl-nspawn@*.service.d \
        "$SC_PRUNE_SHARE_DIR"/*
    do
        [[ -e $path || -L $path ]] || continue
        C="${path##*/}"
        C="${C#srvctl-nspawn@}"
        C="${C%.service.d}"
        C="${C%.service}"
        [[ $registered != *" $C "* ]] && [[ ! -e $SC_PRUNE_SRV_DIR/$C ]] || continue
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
        [[ $registered != *" $C "* ]] && [[ ! -e $SC_PRUNE_SRV_DIR/$C ]] || continue
        ntc "Clearing the failed state of $unit"
        systemctl reset-failed "$unit"
    done 3< <(systemctl list-units 'srvctl-nspawn@*' --state=failed --plain --no-legend)
}
