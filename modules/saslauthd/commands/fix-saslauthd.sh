#!/bin/bash

## @@@ fix-saslauthd
## @en restart saslauthd
## &en This command restarts saslauthd to fix mailing.
## &en It is temporary..

## Operator command: restart the host saslauthd.service (the SMTP AUTH
## backend for host postfix, rimap via the local perdition proxy) and
## report the result. Elevates itself via sudo for non-root callers.

## Guard: refuse to run outside the srvctl dispatcher (module-local exit code).
[[ $SRVCTL ]] || exit 4

## WP-E.2.b: operator command (restart the host mail-auth service) — matches
## this file's own "Operator command" note above.
operators_only
sudomize

if systemctl restart saslauthd
then
    systemctl status saslauthd --no-pager
    msg "Successfully restarted saslauthd"
else
    err "Saslauthd Restart FAILED"
fi
