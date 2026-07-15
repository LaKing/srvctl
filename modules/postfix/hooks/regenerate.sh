#!/bin/bash

##
##   modules/postfix/hooks/regenerate.sh — refresh the relay map.
##
##   Runs via 'run_hook regenerate' from 'sc regenerate' and from the
##   container-creating commands (add-ve, add-ve-user, add-network-ve,
##   add-codepad). Rewrites /etc/postfix/relaydomains from the datastore
##   and postmaps it (libs/postfixlib.sh), then restarts the host
##   postfix.service (libs/systemdlib.sh).
##

## FIXME(v4): low — full restart (not reload) on every regenerate drops
## in-flight SMTP connections even when only the relaydomains map changed;
## and a failed restart aborts the whole invoking command via run_hook's
## exif (see libs/systemdlib.sh).

regenerate_etc_postfix_relaydomains

## Refresh the SMTP TLS cert on every regenerate so a renewed host/wildcard cert
## reaches postfix WITHOUT a full update-install (previously it was installed
## only at update-install, so renewals never propagated to mail). Idempotent —
## re-copies the same bytes when unchanged. Guarded so it is a no-op where the
## certificates module or /etc/postfix is absent.
if command -v install_service_hostcertificate > /dev/null 2>&1 && [[ -d /etc/postfix ]]
then
    install_service_hostcertificate /etc/postfix
fi

restart_postfix
