#!/bin/bash

##
##   modules/named/hooks/regenerate.sh — rebuild the authoritative DNS.
##
##   Runs via 'run_hook regenerate' from 'sc regenerate'. Calls namedcfg
##   (libs/bashlib.sh), which runs named.js to aggregate containers.json
##   from every cluster host and rewrite /var/named/srvctl.conf plus the
##   per-domain zone files, then restart_named (libs/systemdlib.sh) to
##   reload BIND. A nonzero exit from named.js aborts the whole srvctl
##   run via exif in namedcfg.
##

msg "Regenerate bind/named DNS server configuration"

namedcfg

restart_named

## if there are several master name servers, each should be restarted here after a regenerate namedcfg locally
