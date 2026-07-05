#!/bin/bash

##
##   containers/libs/backupcontainerlib.sh — rsync backup of a container.
##
##   backup_ve is used by backup-ve, remove-ve and recreate-ve. Writes
##   backup metadata (container.json, package lists) INTO /srv/$C first,
##   then rsyncs the whole tree to
##   $SC_BACKUP_PATH/srvctl-containers/$C/$NOW — locally, or onto
##   $SC_BACKUP_HOST over ssh when that is set to another machine. A
##   failed rsync aborts the calling command via exif.
##

function backup_ve() { #C

    local C
    C="$1"

    [[ $SC_BACKUP_PATH ]] || SC_BACKUP_PATH=/backup

    ## FIXME(v4): broken root gate — SC_UID0 is the string 'true'/'false',
    ## never empty, so this always passes and the deny branch is dead
    ## (correct form is 'if $SC_UID0').
    if [[ $SC_UID0 ]]
    then

        out container "$C" json > /srv/"$C"/container.json

        # shellcheck disable=SC1090,SC1091 ## runtime-path
        source /srv/"$C"/rootfs/etc/os-release

        if [[ $ID == "fedora" ]]
        then
            msg "Create list of installed packages"
            ## FIXME(v4): 'run' performs no redirection — '>' and the path
            ## are passed to dnf as package specs, dnf errors out and
            ## dnf.packages.list is never written (metadata silently
            ## incomplete).
            run "dnf --installroot=/srv/$C/rootfs list installed > /srv/$C/dnf.packages.list"
            chroot /srv/"$C"/rootfs rpm -qa --qf "%{NAME}\n" | sort > /srv/"$C"/rpm.packages.list
        fi

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
        ## FIXME(v4): bare exit returns 0 — the (dead) deny path would
        ## report success.
        exit
    fi

}