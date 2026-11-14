#!/bin/bash

##
##   containers/libs/removelib.sh — delete a container's directory tree.
##
##   Used by remove-ve and destroy-ve. A container directory can hold mount
##   points of data that is NOT the container's: comount bind-mounts shared
##   storage read-write at /srv/C/comount/NAME (modules/comount), and other
##   containers use the same storage. An 'rm -r' that reaches a live mount
##   deletes that shared data, so the tree is removed only after the unit has
##   stopped and nothing is mounted below it any more.
##

## TEST SEAM for the selftest, not supported configuration.
: "${SC_MOUNTINFO:=/proc/self/mountinfo}"

## Print every mount point below DIR, deepest first.
function mounts_below { ## DIR
    awk -v prefix="$1/" 'index($5, prefix) == 1 { print $5 }' "$SC_MOUNTINFO" | sort -r
}

## Stop container C and delete DIR (its /srv/C). Returns non-zero, with the
## tree left in place, when something stays mounted below it.
function remove_container_tree { ## C DIR
    local C="$1" dir="$2" mp left try

    ## An empty or odd name would turn the path into /srv itself.
    if [[ ! $C =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ $dir != */"$C" ]]
    then
        err "Refusing to remove '$dir' for container '$C'"
        return 22
    fi
    [[ -d $dir ]] || return 0

    ## 'systemctl stop' returns when the unit is down, and the comount mount
    ## units (PartOf= the container unit) stop with it. 'machinectl terminate'
    ## only asks the machine to go away and returns at once.
    run systemctl stop "srvctl-nspawn@$C.service"

    while read -r -u 3 mp
    do
        run umount "$mp"
    done 3< <(mounts_below "$dir")

    left="$(mounts_below "$dir")"
    if [[ -n $left ]]
    then
        err "$C is not removed: still mounted below $dir:"
        printf '%s\n' "$left" >&2
        return 16
    fi

    ## --one-file-system is a second line of defence only: a bind mount of the
    ## same filesystem (comount storage usually is) looks like an ordinary
    ## directory to it, so the mount check above is what protects the data.
    for try in 1 2 3 4 5
    do
        rm -rf --one-file-system -- "$dir"
        [[ -d $dir ]] || return 0
        ntc "$C has still a folder ..."
        sleep "${SC_REMOVE_RETRY_SLEEP:-3}"
    done
    err "$C: could not remove $dir"
    return 1
}
