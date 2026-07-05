#!/bin/bash

##
##   modules/postfix/libs/aliaseslib.sh — /etc/aliases management.
##
##   Sourced via load_libs when SC_USE_POSTFIX=true.
##

## make_aliases_db <rootfs>
## Overwrite $rootfs/etc/aliases with this module's conf/aliases template
## (classic Fedora aliases file, everything forwarded to root) and rebuild
## the lookup db with postalias. Only caller: hooks/update-install-host.sh
## with '' — i.e. the host's own /etc/aliases.
function make_aliases_db() { ## on rootfs
    local rootfs
    rootfs="$1"

    cat "$SC_INSTALL_DIR/modules/postfix/conf/aliases" > "$rootfs/etc/aliases"
    postalias "$rootfs/etc/aliases"
}
