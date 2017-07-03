#!/bin/bash

function userscfg {
    
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/usersonhost/main.js" $*
    
}
