#!/bin/bash

##
##   modules/usersonhost/libs/bashlib.sh — node glue for the usersonhost
##   module. Sourced into the srvctl shell by load_libs when the module
##   is enabled.
##
##   userscfg: runs main.js, the actual user-reconciliation engine
##   (system accounts, passwords, ssh keys, client certs, container
##   share mounts). Called by hooks/regenerate.sh and by
##   regenerate_users (libs/userlib.sh).
##
##   usercfg: runs user.js to write ~/.srvctl/user.conf from users.json,
##   then sources it into the current shell.
##

function userscfg {

    ## arguments are forwarded unquoted on purpose (word splitting);
    ## main.js currently reads argv[2] into CMD but acts on none of it
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/usersonhost/main.js" $*
}

## FIXME(v4): dead code — usercfg has no caller anywhere in the tree; if
## re-enabled, user.js throws for any SC_USER missing from users.json.
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
