#!/bin/bash

##
##   containers/libs/removelib.sh — delete a container.
##
##   remove_ve is the whole of remove-ve and destroy-ve; remove_container_tree
##   deletes the directory. A container directory can hold mount
##   points of data that is NOT the container's: comount bind-mounts shared
##   storage read-write at /srv/C/comount/NAME (modules/comount), and other
##   containers use the same storage. An 'rm -r' that reaches a live mount
##   deletes that shared data, so the tree is removed only after the unit has
##   stopped and nothing is mounted below it any more.
##

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
    done 3< <(mounts_in "$dir")

    left="$(mounts_in "$dir")"
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

## Delete container C: record, unit links, directory tree, and through the
## prune hooks whatever the other modules made for it. With MODE backup the
## tree is copied to the backup path first, and a failed copy ends the command
## before anything is deleted. The caller has checked that the record exists
## and that the user may delete it (existing_container, owner_only).
##
## The record goes before the files: a run that dies in between leaves a
## directory without a record, which container_is_gone does not treat as gone
## and the next regenerate imports again. The other order would leave a
## record that starts a container without files.
function remove_ve { ## C [backup]
    local C="$1" mode="${2:-}" domain_only=false

    msg "Container $C of $(get container "$C" user)"

    ## A domain-only record (retire-ve) has no files to back up, and its unit
    ## was masked by retire-ve: unmask it so a new container of that name can run.
    container_is_domain_only "$C" && domain_only=true

    if [[ $mode == backup ]]
    then
        if $domain_only
        then
            msg "$C is a domain-only record: no container files to back up"
        else
            backup_ve "$C"
        fi
    fi

    ## off the boot target first, so a reboot cannot start it half removed
    rm -f "/etc/systemd/system/machines.target.wants/srvctl-nspawn@$C.service"
    rm -f "$(container_limits_dropin "$C")"

    del container "$C"

    if $domain_only
    then
        run systemctl unmask "srvctl-nspawn@$C.service"
    fi

    ## stop publishing its certificate at the next HAProxy sync
    rm -f -- "${SC_DATASTORE_DIR:?}/cert/$C.pem"

    if ! remove_container_tree "$C" "/srv/$C"
    then
        err "$C: the record is deleted, the files in /srv/$C are not. Unmount what is listed above, then run: rm -rf --one-file-system /srv/$C"
        exit 16
    fi

    ## Record and directory are gone: the shares in the users' homes, the
    ## static docroot, the firewall ports and the rest are leftovers now.
    run_prune

    msg "$C removed."
}
