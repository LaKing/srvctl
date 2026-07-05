#!/bin/bash

##
##   modules/datastore/libs/gitlib.sh — datastore change journal.
##
##   datastore_push, called by the mutating verbs new/put/del in
##   libs/bashlib.sh, commits the json files in the RW datastore with the
##   message "$SC_USER@$HOSTNAME <verb args>" and appends a
##   "$NOW $SC_USER <git output> <verb args>" line to .git.log (which is
##   itself gitignored). In readonly mode it only prints a notice — this is
##   currently the only readonly write protection: the JS-level guard in
##   lib.js never fires (see the FIXME there).
##

function datastore_push() {

    if $SC_DATASTORE_RO_USE
    then
        ntc "Datastore is in readonly mode."
    else
        ## no repository yet (init_datastore_install has not run): skip silently
        [[ ! -d $SC_DATASTORE_RW_DIR/.git ]] && return
        echo "$NOW $SC_USER $(cd "$SC_DATASTORE_RW_DIR" && git add ./*.json && git commit -m "$SC_USER@$HOSTNAME $*") $*" >> "$SC_DATASTORE_RW_DIR/.git.log"
    fi
}
