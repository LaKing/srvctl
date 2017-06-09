#!/bin/bash

function ssh_main {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/ssh/ssh.js" $* 2>&1)"
    exif "SSH-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}

