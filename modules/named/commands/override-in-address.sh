#!/bin/bash

## @@@ override-in-address VE [none|ip]
## @en Override the IN A of the container in named DNS server zone file
## &en Temporary redirect the IN A record.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   modules/named/commands/override-in-address.sh — point a container's
##   wildcard/apex A records (and the reverse proxies) at another IP.
##
##   Host-server-only command. Writes the container datastore key
##   override_in_a_ip ("none" clears the override), then triggers the
##   regenerate_certificates hook and regenerate_haproxy_conf so the
##   reverse proxies pick the new address up. named.js consumes the key
##   at the NEXT full regenerate; this command does not run namedcfg or
##   restart_named itself (see the FIXME below).
##
##   Authorization is manual here instead of the standard authorize
##   helper: the container's owner or reseller is re-executed via
##   sudomize, then the root check gates the datastore write.
##

argument container
C="$ARG"
container_user="$(get container "$C" user)"
exif
container_reseller="$(get container "$C" reseller)"
exif
msg "Container $ARG - $container_user ($container_reseller) - $OPA"

if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then
    sudomize
fi

## Owner/reseller escalated via sudomize above; a non-owner non-root caller
## reaches the deny branch below (WP-E.1: was the always-true '[[ $SC_UID0 ]]').
if $SC_UID0
then
    put container "$C" override_in_a_ip "$OPA"
    run_hook regenerate_certificates
    regenerate_haproxy_conf
    ## FIXME(v4): low — despite the help text, the named zone file is not
    ## regenerated here (no namedcfg/restart_named); the DNS change only
    ## materializes at the next full regenerate.
else
    err "$SC_USER has no access to $C"
    exit 44
fi

## this is actually a setting for all reverse proxies
