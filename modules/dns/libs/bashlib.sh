#!/bin/bash

function dns_scan {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/certificates/dns-scan.js" $* 2>&1)"
    exif "DNS_SCAN-ERROR cfg $* ($?) $__result"
    
    echo "$__result"
}

