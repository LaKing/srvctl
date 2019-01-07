#!/bin/bash

function userscfg {
    
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/usersonhost/main.js" $*
}

function usercfg {
    
    mkdir -p "$SC_HOME/.srvctl"
    
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/usersonhost/user.js" $*
    exif "ERROR USERSONHOST-USERCFG user.js $?"
    
    # shellcheck disable=SC1090
    source "$SC_HOME/.srvctl/user.conf"
    exif "ERROR USERSONHOST-USERCFG source user $?"
}
