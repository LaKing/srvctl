#!/bin/bash

function usersharescfg {
    
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/usershares/main.js" $*
    
}
