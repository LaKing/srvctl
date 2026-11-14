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
##     4. stop the unit and remove /srv/$C, refusing while anything is
##        still mounted below it (remove_container_tree, libs/removelib.sh)
##
##   Safety assumptions: caller is the owner/reseller (sudomize above) or
##   root; the container name is a valid datastore record (checked at the
##   top).
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

# Stop publishing this container's certificate at the next HAProxy sync.
rm -f -- "${SC_DATASTORE_DIR:?}/cert/$C.pem"

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

## Stops the unit, refuses while anything is mounted below /srv/$C (comount
## storage is shared with other containers), then deletes the tree.
if ! remove_container_tree "$C" "/srv/$C"
then
    err "$C: the record is deleted, the files in /srv/$C are not. Unmount what is listed above, then run: rm -rf --one-file-system /srv/$C"
    return 1
fi

## The record and the directory are gone, so every module's prune hook now
## sees this container's artifacts as leftovers.
run_hook prune

msg "$C destroyed."
## sourced context: leave the (now possibly deleted) cwd
cd /srv || return
