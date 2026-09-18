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
##   named_regenerate_activate (libs/acmelib.sh) runs that sequence under the
##   activation lock: it first prepares the DNS-01 challenge zone
##   (_acme.<company-domain>: TSIG key and seed on the primary, replica
##   enablement), and after a successful restart commits the DNS-01 zone
##   manifest bound to the activated srvctl.conf. Overlapping regenerates are
##   serialized, so the manifest letsencrypt issues from always describes the
##   running configuration.
##

msg "Regenerate bind/named DNS server configuration"

named_regenerate_activate
