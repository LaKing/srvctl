#!/bin/bash

function dns_scan {
    msg "DNS scan"
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/dns/dns-scan.js" $*
}

