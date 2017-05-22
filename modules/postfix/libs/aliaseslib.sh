#!/bin/bash

function make_aliases_db() { ## on rootfs
    local rootfs
    rootfs="$1"
    
    cat "$SC_INSTALL_DIR/modules/postfix/conf/aliases" > "$rootfs/etc/aliases"
    postalias "$rootfs/etc/aliases"
}
