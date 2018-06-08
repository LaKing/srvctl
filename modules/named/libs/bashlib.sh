#!/bin/bash

function namedcfg {
    
    #local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    
    /bin/node "$SC_INSTALL_DIR/modules/named/named.js"
    exif "BIND/NAMED-ERROR"
}
