#!/bin/bash

function namedcfg {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/named/named.js" $* 2>&1)"
    exif "BIND/NAMED-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}
