#!/bin/bash

##
##   containers/libs/backupcontainerlib.sh — rsync backup of a container.
##
##   backup_ve is used by backup-ve, remove-ve and recreate-ve. Writes
##   backup metadata (container.json) INTO /srv/$C first,
##   then rsyncs the whole tree to
##   $SC_BACKUP_PATH/srvctl-containers/$C/$NOW — locally, or onto
##   $SC_BACKUP_HOST over ssh when that is set to another machine. A
##   failed rsync aborts the calling command via exif.
##

function backup_ve() { #C

    local C
    C="$1"

    [[ $SC_BACKUP_PATH ]] || SC_BACKUP_PATH=/backup

    ## The callers escalate first (owner_only); nothing here works without uid 0.
    if $SC_UID0
    then
        out container "$C" json > /srv/"$C"/container.json

        ## No package list is made: the copy holds the package database
        ## itself. Making one meant sourcing the container's os-release and
        ## running its rpm in a chroot, both the tenant's code as host root.

        path="$SC_BACKUP_PATH/srvctl-containers/$C/$NOW"

        if [[ "$SC_BACKUP_HOST" ]] && [[ "$SC_BACKUP_HOST" != "$HOSTNAME" ]] && [[ "$SC_BACKUP_HOST" != localhost ]]
        then
            msg "Backup $C to $SC_BACKUP_HOST"
            ## FIXME(v4): HIGH — 'run' does not eval, so the remote shell
            ## receives the single-quoted string as one word ("command not
            ## found"); the remote mkdir never happens and the rsync below
            ## aborts via exif — remote backups are broken whenever
            ## SC_BACKUP_HOST is set.
            run "ssh $SC_BACKUP_HOST 'mkdir -p $path'"
            rsync -aze ssh --info=progress2  /srv/"$C" "$SC_BACKUP_HOST:$path"
            exif
        else
            msg "Backup $C to $path"
            mkdir -p "$path"
            rsync -a --info=progress2  /srv/"$C" "$path"
            exif
        fi

    else
        err "$SC_USER has no access to $ARG"
        exit 44
    fi

}