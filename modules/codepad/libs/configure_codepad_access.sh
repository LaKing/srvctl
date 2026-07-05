#!/bin/bash

##
##   configure_codepad_access — publish user credential files from the
##   datastore into the per-container share tree by running access.js.
##   Used only by this module's regenerate hook. Any node failure aborts
##   the whole srvctl run via exif, with node's exit code.
##

function configure_codepad_access {

    ## historical: access.js does not read this variable, kept for
    ## compatibility with external consumers of the environment
    export SC_ROOTCA_HOST

    ## word-splitting of $* is intentional: pass-through arguments
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/codepad/access.js" $*

    exif "CODEPAD-ACCESS-ERROR cfg $* ($?)"

}
