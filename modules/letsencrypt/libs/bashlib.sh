#!/bin/bash

function letsencrypt_main {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/letsencrypt/letsencrypt.js" $* 2>&1)"
    exif "LETSENCRYPT-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}

