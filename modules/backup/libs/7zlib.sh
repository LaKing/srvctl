#!/bin/bash

## modules/backup/libs/7zlib.sh
##
## 7z-based per-container archive backup. Sourced on every srvctl invocation
## by load_libs while the backup module is enabled; self-disables (return)
## when /usr/bin/7z is not installed.
##
## Provides:
##   local_container_7z_backup CONTAINER [TARGET-DIR]
##       Archive container data to $BACKUP_PATH/$HOSTNAME/CONTAINER (or
##       TARGET-DIR): filelist, creation-date stamp, package list plus
##       "srvctl backup-db clean" inside the container if it answers ssh,
##       then 7z update-mode (u -uq0) archives of cert, rootfs/srv, home,
##       root, etc, var and var/lib/mysql.
##
## No in-repo callers: meant to be called from custom include scripts or via
## "sc exec-function". The function body is currently disabled by a bare
## "exit" (see the FIXME markers below).

## Self-disable when the 7z binary (p7zip) is not available.
if [[ ! -f /usr/bin/7z ]]
then
    return
fi

## FIXME(v4): non-SC_-prefixed config var: the rsync backups (sclib.sh) key off
## SC_BACKUP_PATH, so configuring one leaves the other at its default and the
## two backup flavors write to divergent locations.
[[ $BACKUP_PATH ]] || BACKUP_PATH="/backup"

## backup
# shellcheck disable=SC2317 # intentionally-disabled
function local_container_7z_backup {

    local C to

    C="$1"

    to="$BACKUP_PATH/$HOSTNAME/$C"

    if [[ $2 ]]
    then
        to="$2"
    fi

    ## FIXME(v4): bare "exit" (deliberate disable, e179f53) terminates the whole
    ## calling srvctl process with status 0: callers get a silent "success" and no
    ## backup is made. Everything below is dead code; removing the exit would
    ## activate ~60 untested lines, so it stays until reviewed.
    exit

    mkdir -p "$to"

    msg "local container backup $C to $to"

    ## FIXME(v4): probe compares ssh output to the short name $C; containers whose
    ## internal hostname is an FQDN are misdetected as not running (backup-db clean
    ## and packagelist are then skipped).
    if [[ "$(ssh -n -o ConnectTimeout=1 "$C" hostname 2> /dev/null)" == "$C" ]]
    then
        msg "Container running."

        run ssh "$C" "srvctl backup-db clean"

        if [[ -f "/srv/$C/rootfs/var/log/dnf.log" ]]
        then
            ## FIXME(v4): redirecting "run" captures its colored command-echo line
            ## into packagelist along with the actual package list.
            run ssh "$C" "dnf list installed" > "$to/packagelist"
        fi
    else
        err "Container is not running."
    fi

    run find "/srv/$C" -ls > "$to/filelist"

    if [[ ! -f "$to/creation-date" ]]
    then
        echo "Container created: $(cat "/srv/$C/creation-date" 2> /dev/null)" > "$to/creation-date"
        echo "Backup created: $NOW" >> "$to/creation-date"
    else
        echo "Backup updated: $NOW" >> "$to/creation-date"
    fi

    ntc certificates
    run 7z u -uq0 "$to/cert.7z" "/srv/$C/cert"

    ntc /srv
    if [[ -n "$(ls "/srv/$C/rootfs/srv" 2> /dev/null)" ]]
    then
        run 7z u -uq0 "$to/srv.7z" "/srv/$C/rootfs/srv"
    fi

    ## TODO store an incremental backup of mysql

    ntc /home
    if [[ -n "$(ls "/srv/$C/rootfs/home" 2> /dev/null)" ]]
    then
        run 7z u -uq0 "$to/home.7z" "/srv/$C/rootfs/home"
    fi

    ntc /root
    run 7z u -uq0 "$to/root.7z" "/srv/$C/rootfs/root"

    ntc /etc
    run 7z u -uq0 "$to/etc.7z" "/srv/$C/rootfs/etc"

    ntc /var
    run 7z u -uq0 "$to/var.7z" "/srv/$C/rootfs/var"

    ntc /var/lib/mysql
    if [[ -n "$(ls "/srv/$C/rootfs/var/lib/mysql" 2> /dev/null)" ]]
    then
        run 7z u -uq0 "$to/var-lib-mysql.7z" "/srv/$C/rootfs/var/lib/mysql"
    fi

}
