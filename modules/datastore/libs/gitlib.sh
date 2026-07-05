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
        ## v4 datastore is file-per-entity (hosts/ users/ containers/). Stage
        ## ONLY the entity dirs — NOT `git add -A` over the whole tree, which
        ## would also commit secrets/keys (cert/, users/<name>/) and the
        ## .monolithic-backup archive. Defense in depth: the pathspec keeps
        ## cert/ and .monolithic-backup out entirely, and .gitignore (see
        ## init_datastore_install) excludes the users/<name>/ key dirs while
        ## keeping users/<name>.json records. `-A` still stages entity deletes.
        ## init_datastore_install guarantees the three dirs exist so the
        ## pathspec never errors on an empty type.
        echo "$NOW $SC_USER $(cd "$SC_DATASTORE_RW_DIR" && git add -A -- hosts users containers && git commit -m "$SC_USER@$HOSTNAME $*") $*" >> "$SC_DATASTORE_RW_DIR/.git.log"
    fi
}
