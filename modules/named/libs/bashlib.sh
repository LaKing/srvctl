#!/bin/bash

##
##   modules/named/libs/bashlib.sh — named module lib, auto-loaded when
##   the module is enabled.
##
##   namedcfg runs the zone/config generator named.js (module root),
##   which writes /var/named/srvctl.conf and the per-domain zone files
##   under /var/named/srvctl/. Exit-code contract of named.js: 0 on
##   success, 111 on DATA-ERROR; any nonzero exit aborts the srvctl run
##   via exif. Only called from this module's regenerate hook.
##

function namedcfg {

    /bin/node "$SC_INSTALL_DIR/modules/named/named.js"
    exif "BIND/NAMED-ERROR"
}
