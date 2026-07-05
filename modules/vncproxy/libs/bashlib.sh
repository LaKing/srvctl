#!/bin/bash

## vncproxy module library — loaded into every srvctl shell when the module
## is enabled (load_libs). Note: predates the '[[ $SRVCTL ]] || exit 10'
## guard convention for sourced scripts.

## vncproxycfg [ARGS..] — run vncproxy.js (regenerates /var/vncproxy/records
## from the datastore) and echo its output; abort via exif on failure.
## Only caller in the repo: commands/add-vnc-user.sh.
function vncproxycfg {

    local __result
    ## word-splitting of $* is intentional: args are passed through to node
    # shellcheck disable=SC2048 ## intentional
    # shellcheck disable=SC2086 ## intentional
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/vncproxy/vncproxy.js" $* 2>&1)"
    exif "VNCPROXY-ERROR cfg $* ($?) $__result"

    echo "$__result"
}
