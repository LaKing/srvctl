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
##   main.mjs / lib.js.
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
    fi

    ## Write .gitignore IDEMPOTENTLY (not only on fresh git init) so upgraded
    ## v3 repos also exclude secrets/keys and the migration backup. This is the
    ## second half of the "never commit secrets" guard (see gitlib.sh):
    ##   users/*/   — per-user key dirs (id_ecdsa, .password), keep *.json
    ##   cert/      — private keys
    ##   .monolithic-backup/ — the pre-migration archive
cat > "$SC_DATASTORE_RW_DIR/.gitignore" << EOF
.git.log
.gitignore
.monolithic-backup/
.per-entity
cert/
users/*/
EOF

    ## Guarantee the three entity type dirs exist so datastore_push's
    ## `git add -- hosts users containers` pathspec never errors on an empty
    ## type. per-entity user records live in users/<name>.json; the per-user
    ## key dirs used by ssh/codepad share users/ and coexist (store reads only
    ## *.json). cert/ is unchanged.
    mkdir -p "$SC_DATASTORE_RW_DIR/hosts"
    mkdir -p "$SC_DATASTORE_RW_DIR/users"
    mkdir -p "$SC_DATASTORE_RW_DIR/containers"
    mkdir -p "$SC_DATASTORE_RW_DIR/cert"

    migrate_datastore_to_per_entity
}

## Idempotent one-time conversion of the v3 monolithic RW datastore
## (hosts.json/users.json/containers.json) to the v4 file-per-entity layout
## (hosts/ users/ containers/). Skips once the monolithic files are archived.
function migrate_datastore_to_per_entity() {

    ## Already authoritative: nothing to do. The .per-entity marker (written
    ## below) means per-entity is the source of truth; the monolithic files may
    ## still sit on disk for a half-rsync'd old reader.
    [[ -f "$SC_DATASTORE_RW_DIR/.per-entity" ]] && return 0

    ## No monolithic source → nothing to migrate/consolidate.
    [[ -f "$SC_DATASTORE_RW_DIR/hosts.json" ]] || return 0

    msg "Migrating datastore to file-per-entity layout"

    ## migrate.mjs is write-if-absent + transactional: it CONSOLIDATES any
    ## monolithic records that are missing from per-entity WITHOUT clobbering
    ## existing per-entity records — safe on a half-migrated / split store, and
    ## safe to re-run.
    if run /bin/node "$SC_INSTALL_DIR/modules/datastore/lib/migrate.mjs" "$SC_DATASTORE_RW_DIR" "$SC_DATASTORE_RW_DIR"
    then
        ## Snapshot the pre-migration files, then mark per-entity AUTHORITATIVE.
        ## We deliberately do NOT delete the monolithic originals: a host that is
        ## only HALF rsync'd (new datalib.sh, still-old main.mjs/lib.js) must
        ## keep reading them. The .per-entity marker makes v4 readers ignore the
        ## monolithic (store.mjs) so deletes are honored once we are on v4; a
        ## later fully-v4 cleanup removes the stale originals.
        mkdir -p "$SC_DATASTORE_RW_DIR/.monolithic-backup"
        cp -f "$SC_DATASTORE_RW_DIR/hosts.json" "$SC_DATASTORE_RW_DIR/users.json" "$SC_DATASTORE_RW_DIR/containers.json" "$SC_DATASTORE_RW_DIR/.monolithic-backup/" 2> /dev/null
        : > "$SC_DATASTORE_RW_DIR/.per-entity"
        msg "Datastore migrated; per-entity is now authoritative (.per-entity marker set)"
        return 0
    fi

    ## migrate.mjs exited non-zero (e.g. a partial store — data loss). The
    ## transaction rolled back (no per-entity written) and the monolithic files
    ## are left in place. RETURN NON-ZERO so init_datastore aborts the command
    ## rather than operating on a broken/empty datastore. (err only prints; it
    ## does not set the exit status.)
    err "Datastore migration FAILED; monolithic files left in place — aborting"
    return 1
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
        ## Run install/migration when the per-entity layout is absent, OR when
        ## monolithic files remain and per-entity is NOT yet authoritative
        ## (no .per-entity marker) — i.e. a not-yet / partially migrated store.
        ## Once the marker is set the monolithic files may linger (kept for
        ## half-rsync'd old readers) without re-triggering.
        if [[ ! -d "$SC_DATASTORE_DIR/hosts" ]] || { [[ -f "$SC_DATASTORE_DIR/hosts.json" ]] && [[ ! -f "$SC_DATASTORE_DIR/.per-entity" ]]; }
        then
            ## init_datastore_install ends in migrate_datastore_to_per_entity;
            ## a migration failure (partial store / data loss) must STOP the
            ## command before it runs against a broken datastore. exif exits
            ## with the failing status if init_datastore_install returned != 0.
            init_datastore_install
            exif "datastore init/migration failed"
        fi
    fi

    ## export for main.mjs: the datastore dir AND the effective readonly flag
    ## (v4 enforces readonly in the writer keyed on SC_DATASTORE_RO_USE).
    export SC_DATASTORE_DIR
    export SC_DATASTORE_RO_USE
}
