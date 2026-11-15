#!/bin/bash

##
##   static/libs/prunelib.sh — remove the docroots of removed containers.
##
##   regenerate_static_server (libs/regenerate.sh) seeds a docroot with a
##   placeholder page for every registered container, so the test here is the
##   same record-and-directory test every prune hook uses: a docroot that is
##   pruned is not seeded again.
##

## TEST SEAM for the selftest, not supported configuration.
: "${SC_STATIC_DIR:=/var/srvctl3/storage/static}"

function prune_static_docroots {
    local dir

    for dir in "$SC_STATIC_DIR"/*
    do
        [[ -d $dir ]] || continue
        container_is_gone "${dir##*/}" || continue
        prune "$dir"
    done
}
