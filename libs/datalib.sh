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
    __result="$(/bin/node "$SC_INSTALL_DIR/data.js" get $* 2>&1 )"
    exif "$__result"
    echo "$__result"
}
