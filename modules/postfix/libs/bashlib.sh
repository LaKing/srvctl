#!/bin/bash

function postfixcfg {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/postfix/postfix.js" $* 2>&1)"
    exif "POSTFIX-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}
