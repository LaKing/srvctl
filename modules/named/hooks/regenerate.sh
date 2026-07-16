#!/bin/bash

##
##   modules/named/hooks/regenerate.sh — rebuild the authoritative DNS.
##
##   Runs via 'run_hook regenerate' from 'sc regenerate'. Calls namedcfg
##   (libs/bashlib.sh), which builds a consistent container snapshot and
##   rewrites /var/named/srvctl.conf plus any changed per-domain zone files.
##   restart_named (libs/systemdlib.sh) validates and restarts BIND, then
##   explicitly notifies primary zones or retransfers and verifies replicas. Any
##   generation, activation or propagation failure aborts the srvctl run.
##

msg "Regenerate bind/named DNS server configuration"

namedcfg

restart_named
