#!/bin/bash

function haproxycfg {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/haproxy/haproxy.js" $* 2>&1)"
    exif "HAPROXY-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}
