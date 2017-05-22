#!/bin/bash

function perditioncfg {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/perdition/perdition.js" $* 2>&1)"
    exif "PERDITION-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}
