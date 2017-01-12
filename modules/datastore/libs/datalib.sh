#!/bin/bash

## sc exec-function publish_data

function publish_data() {
    ## simple rsync based data syncronization
    
    local hostlist
    hostlist="$(cfg system host_list)"
    
    for host in $hostlist
    do
        if [[ "$(ssh -n -o ConnectTimeout=1 "$host" hostname 2> /dev/null)" == "$host" ]]
        then
            msg "publishing srvctl data to $host"
            ssh -n -o ConnectTimeout=1 "$host" 'mkdir -p /etc/srvctl' 2> /dev/null
            if ! rsync -avze ssh /etc/srvctl/data "$host:/etc/srvctl"
            then
                err "rsync failed for $host"
            fi
        else
            err "Connection failed for $host"
        fi
    done
}

function grab_data() { ## from-host
    ## simple rsync based data syncronization
    
    local host
    host="$1"
    
    
    if [[ ! -z "$host" ]] && [[ "$(ssh -n -o ConnectTimeout=1 "$host" hostname 2> /dev/null)" == "$host" ]]
    then
        msg "syncing srvctl data from $host"
        mkdir -p /etc/srvctl
        if ! rsync -avze ssh "$host:/etc/srvctl/data" /etc/srvctl
        then
            err "rsync failed for $host"
        fi
    else
        err "Connection failed! $host"
    fi
    
}

function init_datastore() {
    
    msg "init datastore"
    
    ## srvctl3 database is static in /etc/srvctl, shared in /srvctl
    mkdir -p /etc/srvctl/data
    mkdir -p /srvctl/data
    
    if ! [[ -f /etc/srvctl/data/hosts.json ]]
    then
        ntc "INITIALIZE srvctl data hosts"
        echo '{}' > /etc/srvctl/data/hosts.json
    fi
    
    
    if ! [[ -f /srvctl/data/containers.json ]]
    then
        ntc "INITIALIZE srvctl data containers"
        echo '{}' > /srvctl/data/containers.json
    fi
    
    if ! [[ -f /srvctl/data/users.json ]]
    then
        ntc "INITIALIZE srvctl data users"
        echo '{}' > /srvctl/data/users.json
    fi
}
