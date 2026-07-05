#!/bin/bash

## modules/dns/libs/bashlib.sh
##
## DNS scanner glue. Sourced on every srvctl invocation by load_libs while
## the dns module is enabled (SC_USE_DNS=true); defines dns_scan in the
## global shell namespace.
##
## Provides:
##   dns_scan [ARGS]
##       Prints "DNS scan" and runs dns-scan.js synchronously, which
##       resolves A/AAAA/MX/NS via 8.8.8.8 for every domain of every
##       container and rewrites $SC_DATASTORE_DIR/containers.json.
##       Arguments are passed through word-split, but dns-scan.js reads
##       only argv[2] (into CMD) and never uses it; the only in-repo
##       caller (hooks/regenerate.sh) passes none.

function dns_scan {
    msg "DNS scan"
    ## intentional unquoted pass-through of the (unused) arguments
    # shellcheck disable=SC2048,SC2086 # pass-through
    /bin/node "$SC_INSTALL_DIR/modules/dns/dns-scan.js" $*
}
