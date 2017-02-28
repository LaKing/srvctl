#!/bin/bash

function poundcfg {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/pound/pound.js" $* 2>&1)"
    exif "POUND-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}
