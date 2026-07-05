#!/bin/bash

##
##   modules/perdition/libs/bashlib.sh — perdition module lib,
##   auto-loaded when the module is enabled.
##
##   perditioncfg runs perdition.js (rewrites /var/perdition/popmap.re
##   from the datastore) capturing combined stdout+stderr. On a nonzero
##   node exit, exif aborts the entire srvctl run with the
##   PERDITION-ERROR message; on success the captured output is echoed.
##

function perditioncfg {

    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/perdition/perdition.js" $* 2>&1)"
    exif "PERDITION-ERROR cfg $* ($?) $__result"

    echo "$__result"
}
