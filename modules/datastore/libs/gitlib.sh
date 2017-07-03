#!/bin/bash

function datastore_push() {
    
    if $SC_DATASTORE_RO_USE
    then
        ntc "Datastore is in readonly mode."
    else
        [[ ! -d $SC_DATASTORE_RW_DIR/.git ]] && return
        echo "$NOW $SC_USER $(cd "$SC_DATASTORE_RW_DIR" && git add ./*.json && git commit -m "$SC_USER@$HOSTNAME $*") $*" >> "$SC_DATASTORE_RW_DIR/.git.log"
    fi
}
