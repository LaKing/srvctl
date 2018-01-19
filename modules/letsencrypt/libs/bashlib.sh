#!/bin/bash

function letsencrypt_main {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/letsencrypt/letsencrypt.js" $*
}

