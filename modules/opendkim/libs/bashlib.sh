#!/bin/bash

##
##   modules/opendkim/libs/bashlib.sh — node generator wrapper.
##
##   Sourced by load_libs on every srvctl invocation while the opendkim
##   module is enabled. Provides opendkim_main, which runs the
##   modules/opendkim/opendkim.js generator as root capturing
##   stdout+stderr; a nonzero exit aborts the whole srvctl run via exif
##   with node's exit code, otherwise the captured output is echoed.
##   Only in-tree caller: regenerate_opendkim (libs/opendkimlib.sh).
##

function opendkim_main {

    local __result
    ## Assignment kept separate from 'local' so the $? seen by exif is
    ## the node command's exit status. $* is word-split on purpose (no
    ## caller passes arguments today).
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/opendkim/opendkim.js" $* 2>&1)"
    exif "OPENDKIM-ERROR cfg $* ($?) $__result"

    echo "$__result"
}
