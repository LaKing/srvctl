#!/bin/bash

## Functions to help with automated backups.
## this should be called with srvct

if [[ ! -f /usr/bin/7z ]]
then
    return
fi

[[ $BACKUP_PATH ]] || BACKUP_PATH="/mnt/backup"

## backup
function local_container_7z_backup {
    
    
    local C to
    
    C="$1"
    
    to="$BACKUP_PATH/$HOSTNAME/$C"
    
    mkdir -p "$to"
    
    msg "local container backup $C to $to"
    
    if [[ "$(ssh -n -o ConnectTimeout=1 "$C" hostname 2> /dev/null)" == "$C" ]]
    then
        msg "Container running."
        
        run ssh "$C" "srvctl backup-db clean"
        
        if [[ -f "/srv/$C/rootfs/var/log/dnf.log" ]]
        then
            run ssh "$C" "dnf list installed" > "$to/packagelist"
        fi
    else
        err "Container is not running."
    fi
    
    run find "/srv/$C" -ls > "$to/filelist"
    
    if [ ! -f "$to/creation-date" ]
    then
        echo "Container created: $(cat "/srv/$C/creation-date" 2> /dev/null)" > "$to/creation-date"
        echo "Backup created: $NOW" >> "$to/creation-date"
    else
        echo "Backup updated: $NOW" >> "$to/creation-date"
    fi
    
    
    ntc certificates
    run 7z u -uq0 "$to/cert.7z" "/srv/$C/cert"
    
    ntc /srv
    if [[ ! -z "$(ls "/srv/$C/rootfs/srv" 2> /dev/null)" ]]
    then
        run 7z u -uq0 "$to/srv.7z" "/srv/$C/rootfs/srv"
    fi
    
    ## TODO store an incremental backup of mysql
    
    ntc /home
    if [[ ! -z "$(ls "/srv/$C/rootfs/home" 2> /dev/null)" ]]
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
    if [[ ! -z "$(ls "/srv/$C/rootfs/var/lib/mysql" 2> /dev/null )" ]]
    then
        run 7z u -uq0 "$to/var-lib-mysql.7z" "/srv/$C/rootfs/var/lib/mysql"
    fi
    
}


