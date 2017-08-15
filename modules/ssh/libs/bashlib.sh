#!/bin/bash

function ssh_main {
    
    export SC_ROOTCA_HOST
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    # __result="$(/bin/node "$SC_INSTALL_DIR/modules/ssh/ssh.js" $* 2>&1)"
    /bin/node "$SC_INSTALL_DIR/modules/ssh/ssh.js" $*
    
    exif "SSH-ERROR cfg $* ($?)"
    
}

