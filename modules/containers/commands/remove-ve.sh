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
##   storage and /home mounts cleanup, then unit stop and /srv/$C
##   removal (remove_container_tree, libs/removelib.sh).
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
rm -f "$(container_limits_dropin "$C")"

## legacy per-container unit from srvctl v2
if [[ -f /etc/srvctl/containers/$C.service ]]
then
    run systemctl stop "$C"
    run systemctl disable "$C"
    rm -f /etc/srvctl/containers/"$C".service
fi

backup_ve "$C"

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
