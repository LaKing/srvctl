#!/bin/bash

##
##   opendkim/libs/prunelib.sh — remove the DKIM keys of removed containers.
##
##   opendkim.js keeps one key directory per container name (aliases have
##   none) in $SC_DATASTORE_DIR/opendkim. It is a copy: the key itself lives in
##   /srv/C/opendkim and is copied over on every regenerate, and KeyTable and
##   the signing tables are rebuilt from the records, so the directory of a container
##   with neither a record nor a /srv directory is referenced by nothing.
##   /var/opendkim is a mirror of the datastore directory and follows on the
##   next regenerate_opendkim (libs/opendkimlib.sh).
##

function prune_opendkim_keys {
    local dir

    for dir in "$SC_DATASTORE_DIR"/opendkim/*
    do
        [[ -d $dir && ! -L $dir ]] || continue
        container_is_gone "${dir##*/}" || continue
        prune "$dir"
    done
}
