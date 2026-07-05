#!/bin/bash

##
##   modules/datastore/libs/datalib.sh — datastore initialization and
##   cluster data synchronization helpers.
##
##   publish_data / grab_data rsync the static /etc/srvctl/data tree to /
##   from cluster hosts (usable via exec-function; no other in-repo
##   callers). init_datastore_install (root only) creates the RO/RW
##   directories, seeds hosts/containers/users json and git-inits the RW
##   directory. init_datastore, called from hooks/init.sh, picks the RO or
##   RW directory, seeds missing files and exports SC_DATASTORE_DIR for
##   main.js / lib.js.
##

## sc exec-function publish_data

function publish_data() {
    ## simple rsync based data synchronization to every cluster host

    local host hostlist
    hostlist="$(get cluster host_list)"

    for host in $hostlist
    do
        ## reachability probe: the remote hostname must echo back our value
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
    ## simple rsync based data synchronization from one cluster host

    local host
    host="$1"

    if [[ -n "$host" ]] && [[ "$(ssh -n -o ConnectTimeout=1 "$host" hostname 2> /dev/null)" == "$host" ]]
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

## one-time (root) datastore setup: directories, json seeds, git init, and
## the v4 monolithic -> file-per-entity conversion.
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

    ## Fresh install: seed the v3 monolithic source files ONLY when the RW
    ## datastore has neither the per-entity dirs nor monolithic seeds yet.
    ## They are converted to file-per-entity by migrate_datastore_to_per_entity.
    if [[ ! -d "$SC_DATASTORE_RW_DIR/hosts" ]] && [[ ! -f "$SC_DATASTORE_RW_DIR/hosts.json" ]]
    then
        cat /etc/srvctl/hosts.json > "$SC_DATASTORE_RW_DIR/hosts.json"

        if [[ -f /etc/srvctl/data/containers.json ]]
        then
            cat /etc/srvctl/data/containers.json > "$SC_DATASTORE_RW_DIR/containers.json"
        else
            err "INITIALIZE-EMPTY srvctl data containers"
            echo '{}' > "$SC_DATASTORE_RW_DIR/containers.json"
        fi

        if [[ -f /etc/srvctl/data/users.json ]]
        then
            cat /etc/srvctl/data/users.json > "$SC_DATASTORE_RW_DIR/users.json"
        else
            ## seed table: root plus the single-letter resellers a-x
            err "INITIALIZE-DEFAULT srvctl data users"
            cat "$SC_INSTALL_DIR/modules/datastore/default-users.json" > "$SC_DATASTORE_RW_DIR/users.json"
        fi
    fi

    ## the RW datastore is a git repository; datastore_push commits into it
    if [[ ! -d $SC_DATASTORE_RW_DIR/.git ]]
    then
        msg "git init datastore"
        git init -q "$SC_DATASTORE_RW_DIR"

cat > "$SC_DATASTORE_RW_DIR/.gitignore" << EOF
.git.log
.gitignore
.monolithic-backup
EOF
    fi

    ## per-entity user records live in users/<name>.json; the per-user key
    ## dirs used by ssh/codepad share the same users/ dir and coexist (the
    ## store only reads *.json). cert/ is unchanged.
    mkdir -p "$SC_DATASTORE_RW_DIR/users"
    mkdir -p "$SC_DATASTORE_RW_DIR/cert"

    migrate_datastore_to_per_entity
}

## Idempotent one-time conversion of the v3 monolithic RW datastore
## (hosts.json/users.json/containers.json) to the v4 file-per-entity layout
## (hosts/ users/ containers/). Skips once the monolithic files are archived.
function migrate_datastore_to_per_entity() {

    [[ -f "$SC_DATASTORE_RW_DIR/hosts.json" ]] || return 0

    msg "Migrating datastore to file-per-entity layout"

    if run /bin/node "$SC_INSTALL_DIR/modules/datastore/lib/migrate.mjs" "$SC_DATASTORE_RW_DIR" "$SC_DATASTORE_RW_DIR"
    then
        mkdir -p "$SC_DATASTORE_RW_DIR/.monolithic-backup"
        mv "$SC_DATASTORE_RW_DIR/hosts.json" "$SC_DATASTORE_RW_DIR/users.json" "$SC_DATASTORE_RW_DIR/containers.json" "$SC_DATASTORE_RW_DIR/.monolithic-backup/" 2> /dev/null
        msg "Datastore migrated; monolithic files archived to .monolithic-backup"
    else
        err "Datastore migration FAILED; monolithic files left in place"
    fi
}

## select the RO or RW directory, ensure the per-entity layout, export vars
function init_datastore() {

    if $SC_DATASTORE_RO_USE
    then
        SC_DATASTORE_DIR="$SC_DATASTORE_RO_DIR"
        msg "Readonly datastore $SC_DATASTORE_RO_DIR"
    else
        SC_DATASTORE_DIR="$SC_DATASTORE_RW_DIR"
    fi

    ## Ensure the RW datastore is file-per-entity (fresh seed or one-time
    ## migration). Only when writable and root — never mutate the RO copy.
    ## Triggers when the per-entity dir is absent OR monolithic files remain
    ## (a not-yet / partially migrated store); init_datastore_install is
    ## idempotent and no-ops once fully migrated.
    if ! $SC_DATASTORE_RO_USE && [[ $USER == root ]]
    then
        if [[ ! -d "$SC_DATASTORE_DIR/hosts" ]] || [[ -f "$SC_DATASTORE_DIR/hosts.json" ]]
        then
            init_datastore_install
        fi
    fi

    ## export for main.mjs: the datastore dir AND the effective readonly flag
    ## (v4 enforces readonly in the writer keyed on SC_DATASTORE_RO_USE).
    export SC_DATASTORE_DIR
    export SC_DATASTORE_RO_USE
}
