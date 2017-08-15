#!/bin/bash

## sc exec-function publish_data

function publish_data() {
    ## simple rsync based data syncronization
    
    local hostlist
    hostlist="$(cfg cluster host_list)"
    
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

function init_datastore_install() {
    
    if [[ $USER != root ]]
    then
        return
    fi
    
    msg "init_datastore_install"
    
    ## srvctl3 database is static in /etc/srvctl/data, shared in the RW folder
    mkdir -p "$SC_DATASTORE_RO_DIR"
    mkdir -p "$SC_DATASTORE_RW_DIR"
    mkdir -p /etc/srvctl/data
    
    
    ## hosts.json is more or less static data
    if ! [[ -f "$SC_DATASTORE_DIR/hosts.json" ]]
    then
        cat /etc/srvctl/hosts.json > "$SC_DATASTORE_DIR/hosts.json"
    fi
    
    if ! [[ -f "$SC_DATASTORE_DIR/containers.json" ]]
    then
        if [[ -f /etc/srvctl/data/containers.json ]]
        then
            cat /etc/srvctl/data/containers.json > "$SC_DATASTORE_DIR/containers.json"
        else
            err "INITIALIZE-EMPTY srvctl data containers"
            echo '{}' > "$SC_DATASTORE_DIR/containers.json"
        fi
    fi
    
    if ! [[ -f "$SC_DATASTORE_DIR/users.json" ]]
    then
        if [[ -f /etc/srvctl/data/users.json ]]
        then
            cat /etc/srvctl/data/users.json > "$SC_DATASTORE_DIR/users.json"
        else
            err "INITIALIZE-DEFAULT srvctl data users"
            cat "$SC_INSTALL_DIR/modules/datastore/default-users.json" > "$SC_DATASTORE_DIR/users.json"
        fi
    fi
    
    if [[ ! -d $SC_DATASTORE_RW_DIR/.git ]]
    then
        msg "git init datastore"
        git init -q "$SC_DATASTORE_RW_DIR"
        
cat > "$SC_DATASTORE_RW_DIR/.gitignore" << EOF
.git.log
.gitignore
EOF
    fi
    
    
    mkdir -p "$SC_DATASTORE_RW_DIR/users"
    mkdir -p "$SC_DATASTORE_RW_DIR/cert"
    
}

function init_datastore() {
    
    if $SC_DATASTORE_RO_USE
    then
        SC_DATASTORE_DIR="$SC_DATASTORE_RO_DIR"
    else
        SC_DATASTORE_DIR="$SC_DATASTORE_RW_DIR"
    fi
    
    if [[ ! -f $SC_DATASTORE_DIR/hosts.json ]] || [[ ! -f $SC_DATASTORE_DIR/containers.json ]] || [[ ! -f $SC_DATASTORE_DIR/users.json ]]
    then
        init_datastore_install
    fi
    
    export SC_DATASTORE_DIR
}

