#!/bin/bash

##
##   modules/named/libs/bashlib.sh — named module lib, auto-loaded when
##   the module is enabled.
##
##   namedcfg serializes and runs the zone/config generator named.js (module root),
##   which writes /var/named/srvctl.conf and the per-domain zone files
##   under /var/named/srvctl/. Exit-code contract of named.js: 0 on
##   success, 111 on DATA-ERROR; any nonzero exit aborts the srvctl run
##   via exif. Only called from this module's regenerate hook.
##

function namedcfg {
    local require_fresh=true

    ## Interactive, command-driven and all-host regenerations are convergence
    ## operations: publishing an old peer cache as success would hide the very
    ## datastore change the operator is applying. The hourly safety run may use
    ## a recent last-good cache (bounded by named.js) to tolerate a short peer
    ## outage while preserving the already published zone set.
    if [[ $ARG == "#cron.hourly" ]]
    then
        require_fresh=false
    fi
    ## restart_named runs immediately after namedcfg in the same hook shell.
    ## Operator convergence forces and verifies full replica transfers; the
    ## hourly safety pass uses the normal lightweight SOA refresh path.
    # shellcheck disable=SC2034 # consumed by restart_named after this hook
    NAMED_FORCE_RETRANSFER="$require_fresh"

    ## A cron regeneration and a manual regeneration may overlap. Serial
    ## allocation compares the new zone with the currently published file, so
    ## only one generator may perform that read/replace sequence at a time.
    SC_NAMED_REQUIRE_FRESH="$require_fresh" \
    flock --wait 60 /run/srvctl-named-regenerate.lock \
        /bin/node "$SC_INSTALL_DIR/modules/named/named.js"
    exif "BIND/NAMED-ERROR"
}
