#!/bin/bash

## @@@ destroy-ve VE
## @en Delete container with all its files
## &en Delete all files and all records regarding the VE.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/destroy-ve.sh — irreversibly delete a container,
##   its files and its datastore record. NO BACKUP is taken (that is
##   remove-ve, which is this same sequence with backup_ve first).
##
##   Step order (deliberate — record deleted before its files):
##     1. drop the machines.target.wants symlink so the unit cannot come
##        back on boot, and stop/disable a legacy /etc/srvctl/containers
##        unit if one exists
##     2. 'del container' — the record disappears from the cluster before
##        any file is touched, so a crash mid-way leaves an orphan dir
##        (re-importable) rather than a half-deleted live container
##     3. remove the static-storage tree and force-umount + remove every
##        /home/<user>/$C mount (NFS-stale-handle safety, see link below)
##     4. terminate/kill the machine if still registered, then remove
##        /srv/$C in a retry loop (mounts inside may need several passes)
##
##   Safety assumptions: caller is the owner/reseller (sudomize above) or
##   root; the container name is a valid datastore record (checked at the
##   top); nothing else mounts into /srv/$C while this runs.
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

## WP-E.2: root passes, owner/reseller escalates, else denied — before any
## file is removed.
owner_only container "$ARG"

C="$ARG"

rm -fr /etc/systemd/system/machines.target.wants/srvctl-nspawn@"$C".service

## legacy per-container unit from srvctl v2
if [[ -f /etc/srvctl/containers/$C.service ]]
then
    run systemctl stop "$C"
    run systemctl disable "$C"
    rm -f /etc/srvctl/containers/"$C".service
fi

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
## sourced context: leave the (now possibly deleted) cwd
cd /srv || return
