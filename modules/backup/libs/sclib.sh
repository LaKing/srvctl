#!/bin/bash

## modules/backup/libs/sclib.sh
##
## rsync mirror-backup helpers. Sourced on every srvctl invocation by
## load_libs while the backup module is enabled; can also be sourced
## standalone or used as a scripting recipe (see the examples at the end of
## this file).
##
## Provides:
##   local_backup DIR...              backup local directories to
##                                    $SC_BACKUP_PATH/$HOSTNAME/...
##   server_backup HOST DIR...        backup directories from HOST over ssh
##                                    to $SC_BACKUP_PATH/<remote hostname>/...
##   remote_backup PROXY HOST DIR...  backup directories from HOST reached
##                                    through the ssh jump host PROXY to
##                                    $SC_BACKUP_PATH/<remote hostname>/...
##   display_backup_geometry HOST DIR SSIZE DSIZE SCOUNT DCOUNT
##                                    print and log one size/file-count line
##
## Each backup function repeats the same per-directory pattern: validate the
## source, log the start, create the target parent directory, skip when a
## matching rsync already shows up in systemctl status, compute du/find
## geometry when on a TTY, then rsync --delete-after (mirror semantics:
## files deleted at the source get deleted from the backup too) and log
## OK/ERROR to $SC_HOME/.srvctl/backup.log.
##
## No in-repo callers: intended for custom include scripts or
## "sc exec-function".

[[ $SC_BACKUP_PATH ]] || SC_BACKUP_PATH="/backup"

## Print and append to $SC_HOME/.srvctl/backup.log one comparison line:
## host, directory, source/destination sizes and file counts.
function display_backup_geometry() {
    msg "$1:$2 #source-size $3 #destination-size $4 #source-files $5 #destination-files $6"
    echo "$NOW $1:$2 #source-size $3 #destination-size $4 #source-files $5 #destination-files $6" >> "$SC_HOME/.srvctl/backup.log"
}

## local backup from a local folder
function local_backup { ## directories

    local dirs target source_size destination_size source_count destination_count
    local args t i

    args="${*:1}"
    target="$SC_BACKUP_PATH/$HOSTNAME"

    msg "Local backup $args to $target"

    ## FIXME(v4): unquoted expansion word-splits and glob-expands: directory
    ## arguments containing spaces or glob characters fall apart into wrong paths.
    for i in $args
    do
        ## check if we have a real source
        if [[ -d $i ]]
        then
            echo "$NOW backup-local $i" >> "$SC_HOME/.srvctl/backup.log"
        else
            err "$i dont exists"
            continue
        fi

        ## we must create the parent directory so we can rsync to it
        mkdir -p "$target/$(dirname "$i")"

        ## make sure there is no other process doing the same
        ## FIXME(v4): substring match over the whole systemctl status tree: any
        ## unrelated process whose cmdline contains both strings makes this fire
        ## and silently skip this directory's backup.
        if [[ "$(systemctl status | grep rsync | grep "$target" | grep -c "$i")" != "0" ]]
        then
            err "There is a process already running for this backup task."
            systemctl status | grep rsync | grep "$target" | grep "$i"
            echo ''
            continue
        fi

        ## FIXME(v4): geometry is TTY-only, so under cron the size/count vars stay
        ## empty and the OK/ERROR log lines record "#size: / files: /".
        if $SC_TTY
        then
            ntc "Calculating ..."
            ## init comparison variables
            source_size=0
            destination_size=0
            source_count=0
            destination_count=0

            ## populate comparison variables
            source_size="$(du -hs --apparent-size "$i")"

            if [[ -d "$target/$i" ]]
            then
                destination_size="$(du -hs --apparent-size "$target/$i")"
            fi

            source_count="$(find "$i" | wc -l)"
            if [[ -d "$target/$i" ]]
            then
                destination_count="$(find "$target/$i" | wc -l)"
            fi

            ## display comparison variables
            display_backup_geometry "$HOSTNAME" "$i" "$source_size" "$destination_size" "$source_count" "$destination_count"
        fi

        ## perform the task
        t="$target/$(dirname "$i")"

        nur rsync --progress --delete-after -a "$i" "$t"
        if rsync --progress --delete-after -a "$i" "$t"
        then
            msg "OK backup done $HOSTNAME:$i"
            echo "$NOW OK local-backup $i #size: $source_size/$destination_size files: $source_count/$destination_count" >> "$SC_HOME/.srvctl/backup.log"
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
    local host hostname t s i

    host="$1"

    msg "Connecting to $host"

    if hostname="$(ssh -n -o BatchMode=yes "$host" hostname)"
    then
        msg "Connected to $hostname"
    else
        err "Connection to $host failed."
        return
    fi

    dirs="${*:2}"

    target="$SC_BACKUP_PATH/$hostname"

    msg "Server backup $host $dirs to $target"

    ## FIXME(v4): unquoted expansion word-splits and glob-expands: directory
    ## arguments containing spaces or glob characters fall apart into wrong paths.
    for i in $dirs
    do
        ## check if we have a real source
        # shellcheck disable=SC2029
        if ssh -n -o BatchMode=yes "$host" "[[ -d $i ]]"
        then
            echo "$NOW backup $host $i" >> "$SC_HOME/.srvctl/backup.log"
        else
            err "$i inaccessible on $host"
            continue
        fi

        mkdir -p "$target/$(dirname "$i")"

        ## make sure there is no other process doing the same
        ## FIXME(v4): substring match over the whole systemctl status tree: any
        ## unrelated process whose cmdline contains both strings makes this fire
        ## and silently skip this directory's backup.
        if [[ "$(systemctl status | grep rsync | grep "$target" | grep -c "$i")" != "0" ]]
        then
            err "There is a process already running for this backup task."
            systemctl status | grep rsync | grep "$target" | grep "$i"
            echo ''
            continue
        fi

        ## FIXME(v4): geometry is TTY-only, so under cron the size/count vars stay
        ## empty and the OK/ERROR log lines record "#size: / files: /".
        if $SC_TTY
        then
            ntc "Calculating ..."
            ## init comparison variables
            source_size=0
            destination_size=0
            source_count=0
            destination_count=0

            ## populate comparison variables
            # shellcheck disable=SC2029
            source_size="$(ssh -n -o BatchMode=yes "$host" "du -hs --apparent-size $i")"
            if [[ -d "$target/$i" ]]
            then
                destination_size="$(du -hs --apparent-size "$target/$i")"
            fi

            # shellcheck disable=SC2029
            source_count="$(ssh -n -o BatchMode=yes "$host" "find $i | wc -l")"
            if [[ -d "$target/$i" ]]
            then
                destination_count="$(find "$target/$i" | wc -l)"
            fi

            ## display comparison variables
            display_backup_geometry "$host" "$i" "$source_size" "$destination_size" "$source_count" "$destination_count"

        fi

        ## perform the task
        t="$target/$(dirname "$i")"
        s="$host:$i"
        nur rsync --progress --delete-after -avze ssh "$s" "$t"


        if rsync --progress --delete-after -avze ssh "$s" "$t"
        then
            msg "OK backup done $host:$i"
            echo "$NOW OK $host $i #size: $source_size/$destination_size files: $source_count/$destination_count" >> "$SC_HOME/.srvctl/backup.log"
        else
            ## FIXME(v4): mislabeled "local-backup-failure" (copy-paste from
            ## local_backup): remote failures are indistinguishable from local
            ## ones when grepping backup.log.
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
    local host hostname proxy t s p i

    proxy="$1"
    host="$2"

    msg "Connecting to $host via $proxy"

    # shellcheck disable=SC2029
    if hostname="$(ssh -n -o BatchMode=yes "$proxy" "ssh -n -o BatchMode=yes $host hostname")"
    then
        msg "Connected to $hostname"
    else
        err "Connection to $host via $proxy failed."
        return
    fi

    dirs="${*:3}"
    target="$SC_BACKUP_PATH/$hostname"

    msg "remote backup $proxy $host $dirs to $target"

    ## FIXME(v4): unquoted expansion word-splits and glob-expands: directory
    ## arguments containing spaces or glob characters fall apart into wrong paths.
    for i in $dirs
    do
        ## check if we have a real source
        # shellcheck disable=SC2029
        if ssh -n -o BatchMode=yes "$proxy" "ssh -n -o BatchMode=yes $host [[ -d $i ]]"
        then
            echo "$NOW backup $proxy -> $host $i" >> "$SC_HOME/.srvctl/backup.log"
        else
            err "$i inaccessible on $host"
            continue
        fi

        mkdir -p "$target/$(dirname "$i")"

        ## make sure there is no other process doing the same
        ## FIXME(v4): substring match over the whole systemctl status tree: any
        ## unrelated process whose cmdline contains both strings makes this fire
        ## and silently skip this directory's backup.
        if [[ "$(systemctl status | grep rsync | grep "$target" | grep -c "$i")" != "0" ]]
        then
            err "There is a process already running for this backup task."
            systemctl status | grep rsync | grep "$target" | grep "$i"
            echo ''
            continue
        fi

        ## FIXME(v4): geometry is TTY-only, so under cron the size/count vars stay
        ## empty and the OK/ERROR log lines record "#size: / files: /".
        if $SC_TTY
        then
            ntc "Calculating ..."
            ## init comparison variables
            source_size=0
            destination_size=0
            source_count=0
            destination_count=0

            ## populate comparison variables
            # shellcheck disable=SC2029
            source_size="$(ssh -n -o BatchMode=yes "$proxy" ssh -n -o BatchMode=yes "$host" "du -hs --apparent-size $i")"
            if [[ -d "$target/$i" ]]
            then
                destination_size="$(du -hs --apparent-size "$target/$i")"
            fi

            # shellcheck disable=SC2029
            source_count="$(ssh -n -o BatchMode=yes "$proxy" ssh -n -o BatchMode=yes "$host" "find $i | wc -l")"
            if [[ -d "$target/$i" ]]
            then
                destination_count="$(find "$target/$i" | wc -l)"
            fi

            ## display comparison variables
            display_backup_geometry "$host" "$i" "$source_size" "$destination_size" "$source_count" "$destination_count"
        fi

        ## perform the task

        t="$target/$(dirname "$i")"
        ## FIXME(v4): reachability was probed above as plain $host but the transfer
        ## runs as root@$host: probe and transfer can disagree on the ssh user.
        s="root@$host:$i"
        p="ssh -A $proxy ssh"

        nur rsync --progress --delete-after -avz -e "$p" "$s" "$t"


        if rsync --progress --delete-after -avz -e "$p" "$s" "$t"
        then
            msg "OK backup done $host:$i"
            echo "$NOW OK $host $i #size: $source_size/$destination_size files: $source_count/$destination_count" >> "$SC_HOME/.srvctl/backup.log"
        else
            ## FIXME(v4): mislabeled "local-backup-failure" (copy-paste from
            ## local_backup): remote failures are indistinguishable from local
            ## ones when grepping backup.log.
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
