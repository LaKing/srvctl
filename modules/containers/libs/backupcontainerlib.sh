#!/bin/bash

function backup_ve() { #C
    
    local C
    C="$1"
    
    [[ $SC_BACKUP_PATH ]] || SC_BACKUP_PATH=/backup
    
    if [[ $SC_UID0 ]]
    then
        
        out container "$C" json > /srv/"$C"/container.json
        
        # shellcheck source=/etc/os-release
        source /srv/"$C"/rootfs/etc/os-release
        
        if [[ $ID == "fedora" ]]
        then
            msg "Create list of installed packages"
            run "dnf --installroot=/srv/$C/rootfs list installed > /srv/$C/dnf.packages.list"
            chroot /srv/"$C"/rootfs rpm -qa --qf "%{NAME}\n" | sort > /srv/"$C"/rpm.packages.list
        fi
        
        path="$SC_BACKUP_PATH/srvctl-containers/$C/$NOW"
        
        if [[ "$SC_BACKUP_HOST" ]] && [[ "$SC_BACKUP_HOST" != "$HOSTNAME" ]] && [[ "$SC_BACKUP_HOST" != localhost ]]
        then
            msg "Backup $C to $SC_BACKUP_HOST"
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
        exit
    fi
    
}