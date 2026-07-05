#!/bin/bash

##
##   modules/ssh/libs/sshlib.sh — node generator wrapper.
##
##   Sourced by load_libs on every srvctl invocation while the ssh
##   module is enabled. Provides ssh_main, which exports SC_ROOTCA_HOST
##   for the generator (currently not read there) and runs
##   modules/ssh/ssh.js — ssh_config.d drop-ins, cluster host-key scan,
##   known_hosts files and user public-key distribution. A nonzero node
##   exit aborts the whole srvctl run via exif with node's exit code;
##   the hooks depend on this failing loudly. In-tree callers:
##   regenerate_ssh_config and update_install_ssh_config
##   (libs/bashlib.sh).
##

function ssh_main {

    export SC_ROOTCA_HOST

    ## $* is word-split on purpose (no caller passes arguments today).
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/ssh/ssh.js" $*

    exif "SSH-ERROR cfg $* ($?)"

}
