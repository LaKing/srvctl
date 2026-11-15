#!/bin/bash

##
##   datastore/libs/prunelib.sh — remove the v3 single-file datastore.
##
##   The migration to one file per record (datalib.sh,
##   migrate_datastore_to_per_entity) left hosts.json, users.json and
##   containers.json in place and copied them to .monolithic-backup. With the
##   .per-entity marker set nothing reads them, but they are not harmless: if
##   the marker is ever lost (a copy or restore that drops hidden files), the
##   next command migrates again and every container and user deleted since
##   comes back. Without the three files a marker-less store is simply marked
##   authoritative again.
##
##   All three go or none: the migration treats a store with users.json or
##   containers.json but no hosts.json as broken.
##

function prune_monolithic_datastore {
    local dir="$SC_DATASTORE_RW_DIR" type
    local -a files=()

    [[ -f $dir/.per-entity ]] || return 0

    for type in hosts users containers
    do
        [[ -e $dir/$type.json || -L $dir/$type.json ]] || continue
        ## The backup copy proves this is the file the migration read, not
        ## something written by hand later.
        if ! cmp -s "$dir/$type.json" "$dir/.monolithic-backup/$type.json"
        then
            err "$dir/$type.json differs from its copy in .monolithic-backup: the single-file datastore is not removed"
            return 0
        fi
        files+=("$dir/$type.json")
    done

    ((${#files[@]} == 0)) || prune "${files[@]}"
}
