#!/bin/bash

function opendkim_main {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/opendkim/opendkim.js" $* 2>&1)"
    exif "OPENDKIM-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}

