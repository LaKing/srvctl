#!/bin/bash

##
##   modules/perdition/hooks/regenerate.sh — refresh mail-proxy routing.
##
##   Sourced by 'run_hook regenerate' (add-ve, add-ve-user,
##   add-network-ve, add-codepad, the regenerate command, regenlib.sh).
##   perditioncfg (libs/bashlib.sh) rewrites /var/perdition/popmap.re
##   from the datastore's containers.json via perdition.js, then
##   restart_perdition (libs/systemdlib.sh) restarts the imap4s, imap4
##   and pop3s services.
##

## Refresh the IMAP/POP TLS cert so a renewal reaches perdition without a full
## update-install. Guarded: only when installed (the certificates module and
## /etc/perdition present) — perdition is not installed on every host.
if command -v install_service_hostcertificate > /dev/null 2>&1 && [[ -d /etc/perdition ]]
then
    install_service_hostcertificate /etc/perdition
fi

perditioncfg

restart_perdition

## FIXME(v4): high — on a fresh host the perdition installer never runs
## (hooks/update-install-host.sh), so /var/perdition does not exist and
## perditioncfg aborts the whole command via exif (perdition.js exits
## 111 on the ENOENT write). The hook needs an installed-state guard,
## or the module retired for the G9 mail proxy.

## The trailing 'return 0' is load-bearing: restart_perdition ends with
## a nonzero status when a unit is down, and run_hook's exif would
## abort the entire regenerate without it.
return 0
