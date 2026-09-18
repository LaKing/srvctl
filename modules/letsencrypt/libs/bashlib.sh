#!/bin/bash

##
##   letsencrypt/libs/bashlib.sh — node shim.
##
##   Sourced by load_libs whenever the letsencrypt module is enabled.
##   letsencrypt_main runs modules/letsencrypt/letsencrypt.js, which drives
##   'letsencrypt certonly' for every eligible container domain and deploys
##   the resulting privkey+fullchain+ca bundles (see the letsencrypt.js
##   header), under the letsencrypt run lock. Its only caller,
##   regenerate_letsencrypt (letsencryptlib.sh),
##   passes no arguments; $* is forwarded unquoted on purpose (plain
##   word-splitting shim, arguments never contain whitespace).
##

function letsencrypt_main {

    ## one letsencrypt.js at a time: it owns the handover state, the journal
    ## and the certbot lineages (a second caller waits up to 10 minutes)
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    flock -w 600 "${SC_LETSENCRYPT_LOCK:-/run/srvctl-letsencrypt.lock}" \
        /bin/node "$SC_INSTALL_DIR/modules/letsencrypt/letsencrypt.js" $*
}
