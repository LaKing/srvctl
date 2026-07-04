#!/bin/bash

function vncproxycfg {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/vncproxy/vncproxy.js" $* 2>&1)"
    exif "VNCPROXY-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}
