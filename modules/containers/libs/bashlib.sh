#!/bin/bash

##
##   containers/libs/bashlib.sh — bridge to the node status table.
##
##   containers_status backs 'sc status' (no argument): renders the
##   cluster container table via status.js, which reads the datastore
##   JSON directly and probes unit state/ping per container.
##

function containers_status {
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/containers/status.js" $* 2>&1

}
