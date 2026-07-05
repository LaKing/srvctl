#!/bin/bash

##
##   haproxy/libs/bashlib.sh — node renderer wrapper.
##
##   Sourced by load_libs when the haproxy module is enabled. Internal to
##   the module: regenerate_haproxy_conf (proxylib.sh) is the only caller.
##

## haproxycfg: run haproxy.js, which renders and writes
## /etc/haproxy/haproxy.cfg from the datastore. Captures stdout+stderr;
## on a non-zero exit (111 write error, 99 abnormal) exif aborts the CLI
## with that code, otherwise the node output is echoed through.
function haproxycfg {

    local __result
    ## word-splitting of $* is intentional: pass any args through verbatim
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/haproxy/haproxy.js" $* 2>&1)"
    exif "HAPROXY-ERROR cfg $* ($?) $__result"

    echo "$__result"
}
