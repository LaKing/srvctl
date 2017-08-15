#!/bin/bash

[[ $SC_BACKUP_PATH ]] || SC_BACKUP_PATH="/backup"


## local backup from a local folder
function local_backup { ## directories
    
    local dirs target source_size destination_size source_count destination_count
    
    args="${@:1}"
    target="$SC_BACKUP_PATH/$HOSTNAME"
    
    for i in $args
    do
        ## check oif have a real source
        if [[ -d $i ]]
        then
            echo "$NOW backup-local $i" >> "$SC_HOME/.srvctl/backup.log"
        else
            err "$i dont exists"
            continue
        fi
        
        ## we must create the parent directory so we can rsync to it
        mkdir -p "$target/$(dirname "$i")"
        
        ## mae sure there is no other process doing the same
        if [[ "$(systemctl status | grep rsync | grep "$target" | grep "$i" | wc -l)" != "0" ]]
        then
            err "There is a process already running for this backup task."
            systemctl status | grep rsync | grep "$target" | grep "$i"
            echo ''
            continue
        fi
        
        ## init comparison variables
        source_size=0
        destination_size=0
        source_count=0
        destination_count=0
        
        ## populate comparison variables
        source_size="$(du -hs --apparent-size "$i" | awk '{print $1}')"
        if [[ -d "$target/$i" ]]
        then
            destination_size="$(du -hs --apparent-size "$target/$i" | awk '{print $1}')"
        fi
        
        source_count="$(find "$i" | wc -l)"
        if [[ -d "$target/$i" ]]
        then
            destination_count="$(find "$target/$i" | wc -l)"
        fi
        
        ## display comparison variables
        msg "local-backup: $i #size: $source_size/$destination_size files: $source_count/$destination_count"
        
        ## perform the task
        if run rsync --delete -a "$i" "$target/$(dirname "$i")"
        then
            msg "OK backup done $HOSTNAME:$i"
            echo "$NOW local-backup OK: $i #size: $source_size/$destination_size files: $source_count/$destination_count" >> "$SC_HOME/.srvctl/backup.log"
        else
            echo "$NOW !!! ERROR $? !! local-backup-failure: $i #size: $source_size/$destination_size files: $source_count/$destination_count" >> "$SC_HOME/.srvctl/backup.log"
            err "backup error $HOSTNAME:$i"
            
        fi
        echo ''
        
    done
    echo ''
}

## local backup from a server
function server_backup { #datahost #directories
    
    local dirs target source_size destination_size source_count destination_count
    local host hostname
    
    host="$1"
    
    msg "Connecting to $host"
    
    if hostname="$(ssh -n -o BatchMode=yes "$host" hostname)"
    then
        msg "Connected to $hostname"
    else
        err "Connection to $host failed."
        return
    fi
    
    dirs="${@:2}"
    target="$SC_BACKUP_PATH/$hostname"
    
    
    for i in $dirs
    do
        ## check oif have a real source
        if ssh -n -o BatchMode=yes "$host" "[[ -d $i ]]"
        then
            echo "$NOW backup $host $i" >> "$SC_HOME/.srvctl/backup.log"
        else
            err "$i inaccessible on $host"
            continue
        fi
        
        mkdir -p "$target/$(dirname "$i")"
        
        if [ "$(systemctl status | grep rsync | grep "$target" | grep "$i" | wc -l)" != "0" ]
        then
            err "There is a process already running for this backup task."
            systemctl status | grep rsync | grep "$target" | grep "$i"
            echo ''
            continue
        fi
        
        ## init comparison variables
        source_size=0
        destination_size=0
        source_count=0
        destination_count=0
        
        ## populate comparison variables
        source_size="$(ssh -n -o BatchMode=yes "$host" "du -hs --apparent-size $i | awk '{print $1}'")"
        if [[ -d "$target/$i" ]]
        then
            destination_size="$(du -hs --apparent-size "$target/$i" | awk '{print $1}')"
        fi
        
        source_count="$(ssh -n -o BatchMode=yes "$host" "find $i | wc -l")"
        if [[ -d "$target/$i" ]]
        then
            destination_count="$(find "$target/$i" | wc -l)"
        fi
        
        ## display comparison variables
        msg "$host backup: $i #size: $source_size/$destination_size files: $source_count/$destination_count"
        
        ## perform the task
        if run rsync --delete -aze ssh "$host:$i" "$target/$(dirname "$i")"
        then
            msg "OK backup done $host:$i"
            echo "$NOW local-backup OK: $i #size: $source_size/$destination_size files: $source_count/$destination_count" >> "$SC_HOME/.srvctl/backup.log"
        else
            echo "$NOW !!! ERROR $? !! local-backup-failure: $i #size: $source_size/$destination_size files: $source_count/$destination_count" >> "$SC_HOME/.srvctl/backup.log"
            err "backup error $host:$i"
            
        fi
        echo ''
        
    done
    echo ''
}

## local backup of a host thru an ssh-tunneling proxy-server
function remote_backup { #proxyhost #datahost #directories
    
    local dirs target source_size destination_size source_count destination_count
    local host hostname proxy
    
    proxy="$1"
    host="$2"
    
    msg "Connecting to $host via $proxy"
    if hostname="$(ssh -n -o BatchMode=yes "$proxy" "ssh -n -o BatchMode=yes $host hostname")"
    then
        msg "Connected to $hostname"
    else
        err "Connection to $host via $proxy failed."
        return
    fi
    
    dirs="${@:3}"
    target=$SC_BACKUP_PATH/$hostname
    
    for i in $dirs
    do
        ## check oif have a real source
        if ssh -n -o BatchMode=yes "$proxy" "ssh -n -o BatchMode=yes $host [[ -d $i ]]"
        then
            echo "$NOW backup $proxy -> $host $i" >> "$SC_HOME/.srvctl/backup.log"
        else
            err "$i inaccessible on $host"
            continue
        fi
        
        mkdir -p "$target/$(dirname "$i")"
        
        if [ "$(systemctl status | grep rsync | grep "$target" | grep "$i" | wc -l)" != "0" ]
        then
            err "There is a process already running for this backup task."
            systemctl status | grep rsync | grep "$target" | grep "$i"
            echo ''
            continue
        fi
        
        
        ## init comparison variables
        source_size=0
        destination_size=0
        source_count=0
        destination_count=0
        
        ## populate comparison variables
        source_size="$(ssh -n -o BatchMode=yes "$proxy" ssh -n -o BatchMode=yes "$host" "du -hs --apparent-size $i | awk '{print $1}'")"
        if [[ -d "$target/$i" ]]
        then
            destination_size="$(du -hs --apparent-size "$target/$i" | awk '{print $1}')"
        fi
        
        source_count="$(ssh -n -o BatchMode=yes "$proxy" ssh -n -o BatchMode=yes "$host" "find $i | wc -l")"
        if [[ -d "$target/$i" ]]
        then
            destination_count="$(find "$target/$i" | wc -l)"
        fi
        
        ## display comparison variables
        msg "$proxy $host backup: $i #size: $source_size/$destination_size files: $source_count/$destination_count"
        
        ## perform the task
        if rrsync --delete -avz -e "ssh -A $proxy ssh" "$host:$i" "$target/$(dirname "$i")"
        then
            msg "OK backup done $host:$i"
            echo "$NOW local-backup OK: $i #size: $source_size/$destination_size files: $source_count/$destination_count" >> "$SC_HOME/.srvctl/backup.log"
        else
            echo "$NOW !!! ERROR $? !! local-backup-failure: $i #size: $source_size/$destination_size files: $source_count/$destination_count" >> "$SC_HOME/.srvctl/backup.log"
            err "backup error $host:$i"
            
        fi
        echo ''
        
    done
    echo ''
}



## examples:
## create a local backup

#local_backup /etc /root /srv

## create a remote backup

#server_backup s1.example.com /etc /root
#server_backup s2.example.com /etc /root

## create a remote tunneled backup

#remote_backup example.com 10.9.8.7 /etc /srv /mnt

## either add your own settings here, or source this file

