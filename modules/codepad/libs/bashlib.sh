#!/bin/bash

function configure_codepad_access {
    
    export SC_ROOTCA_HOST
    
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/codepad/access.js" $*
    
    exif "CODEPAD-ACCESS-ERROR cfg $* ($?)"
    
}
