#!/bin/bash
##
## Usage:
## myvar="$(get main story)" || exit
## echo "Returned: $myvar"
##
##

function get {
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/data.js" get $* 2>&1 )"
    exif "$__result"
    echo "$__result"
}

function put {
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/data.js" put $* 2>&1 )"
    exif "$__result"
    echo "$__result"
}

function out {
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/data.js" out $* 2>&1
    exif 'Error in data processing, the node-data exited with a failure.'
}
