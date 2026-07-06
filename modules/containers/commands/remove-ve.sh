#!/bin/bash

## @@@ remove-ve VE
## @en Remove container with all its files
## &en All files will be in a 7z format archive in the users home/.srvctl directory.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/remove-ve.sh — back up a container, then delete
##   it. Identical to destroy-ve.sh except that backup_ve runs before
##   'del container' (see destroy-ve.sh for the step-order rationale).
##
##   FIXME(v4): the multi-line help above still describes the old 7z
##   archive into home/.srvctl; the actual backup is an rsync tree under
##   $SC_BACKUP_PATH/srvctl-containers/$C/$NOW (backupcontainerlib.sh).
##   FIXME(v4): 90% duplicate of destroy-ve.sh — collapse in v4.
##
##   Step order: unhook the unit from machines.target, stop a legacy v2
##   unit if present, backup_ve (aborts the command on rsync failure —
##   this is the point of no return), then datastore delete, static
##   storage and /home mounts cleanup, machine terminate/kill, and the
##   /srv/$C removal retry loop.
##

argument container
authorize

if [[ "$(get container "$ARG" exist)" == false ]]
then
    err "Container does not exist."
    exit 0
fi

container_user="$(get container "$ARG" user)"
container_reseller="$(get container "$ARG" reseller)"

msg "Container $ARG - $container_user ($container_reseller)"

## the container owner and its reseller may act as root
if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then
    sudomize
fi

## Owner/reseller escalated via sudomize above; a non-owner non-root caller
## reaches the deny branch below (WP-E.1: was the always-true '[[ $SC_UID0 ]]').
if $SC_UID0
then

    C="$ARG"

    rm -fr /etc/systemd/system/machines.target.wants/srvctl-nspawn@"$C".service

    ## legacy per-container unit from srvctl v2
    if [[ -f /etc/srvctl/containers/$C.service ]]
    then
        run systemctl stop "$C"
        run systemctl disable "$C"
        rm -f /etc/srvctl/containers/"$C".service
    fi

    backup_ve "$C"

    del container "$C"

    rm -fr /var/srvctl3/storage/static/"$C"

    ## https://www.cyberciti.biz/tips/nfs-stale-file-handle-error-and-solution.html

    for uh in /home/*
    do
        if [[ -d "$uh"/"$C" ]]
        then
            for mp in "$uh"/"$C"/*
            do
                run umount -f "$mp"
                run rm -fr "$mp"
            done
            run rm -fr "$uh"/"$C"
        fi
    done

    run sleep 3

    ## TODO check if it is running
    if run machinectl status "$C" 2> /dev/null
    then
        run machinectl terminate "$C"
        run machinectl kill "$C"
    fi

    ## FIXME(v4): unbounded loop — a busy or stale mount inside /srv/$C
    ## retries forever at 3s intervals, and rm -fr may descend into
    ## still-mounted data; bound the retries and umount first.
    while [[ -d /srv/$C ]]
    do
        rm -fr "/srv/$C"
        if [[ -d /srv/$C ]]
        then
            ntc "$C has still a folder ..."
            sleep 3
        fi
    done

    msg "$C destroyed."

else
    err "$SC_USER has no access to $ARG"
    exit 44
fi