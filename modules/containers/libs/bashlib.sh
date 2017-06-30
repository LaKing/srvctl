#!/bin/bash

function containers_status {
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/containers/status.js" $* 2>&1
    
}
