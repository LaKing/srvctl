#!/bin/bash
##
## Usage:
## myvar="$(get container mydomain.ve ip)" || exit
## echo "Returned: $myvar"
##
##

function new {
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/datastore/data.js" new $* 2>&1
    exif 'Error in data processing, the node-datastore module exited with a failure. (new)'
}

function get {
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/data.js" get $* 2>&1 )"
    exif "$__result"
    echo "$__result"
}

function put {
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/data.js" put $* 2>&1 )"
    exif "$__result"
    echo "$__result"
}

function out {
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/datastore/data.js" out $* 2>&1
    exif 'Error in data processing, the node-datastore exited with a failure. (out)'
}

function cfg {
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/datastore/data.js" cfg $* 2>&1
    exif 'Error in data processing, the node-datastore module exited with a failure. (cfg)'
}

function del {
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/datastore/data.js" del $* 2>&1
    exif 'Error in data processing, the node-datastore module exited with a failure. (del)'
}
