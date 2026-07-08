#!/bin/bash

## @@@ testsaslauthd user@ve
## @en test a given user of a container for email-functionality
## &en This command runs the testsaslauthd command, with the password automatically filled in..

## Diagnostic command: end-to-end SMTP AUTH check for one container mail
## user. Reads the user's plaintext password from the container home
## (mail.<domain> takes precedence when both containers exist) and feeds
## it to the cyrus-sasl testsaslauthd utility, exercising the full
## saslauthd -> perdition -> mail-container login chain.

## Guard: refuse to run outside the srvctl dispatcher (module-local exit code).
[[ $SRVCTL ]] || exit 4

## WP-E.2.b: co-worker email diagnostic -> root or operator (was root_only).
operators_only
hs_only

## An operator (non-root) passes operators_only and escalates here via sudomize
## (with operators_only this is no longer dead code — it fires for operators).
sudomize

## Split ARG ("user@domain") into its parts.
## FIXME(v4): no argument validation — with $ARG empty or malformed the script
## still proceeds and attempts a real authentication with an empty username.
user="$(echo "$ARG" | cut -d'@' -f1)"
domain="$(echo "$ARG" | cut -d'@' -f2)"

## Look up the user's mailbox password; when both containers exist,
## mail.<domain> overrides plain <domain>.
## FIXME(v4): password is never initialized, so an exported "password"
## environment variable silently survives when no file is found; $domain/$user
## are unquoted inside [ ], so hostile args break the test expression.
if [ -f /srv/$domain/rootfs/home/$user/.password ]
then
    msg "Container $domain"
    password="$(cat /srv/$domain/rootfs/home/$user/.password)"
fi

if [ -f /srv/mail.$domain/rootfs/home/$user/.password ]
then
    msg "Container mail.$domain"
    password="$(cat /srv/mail.$domain/rootfs/home/$user/.password)"
fi

## FIXME(v4): this branch reports failure but does not exit — execution falls
## through to a pointless auth attempt with an empty password, and the exit
## status comes from testsaslauthd instead of a clean error.
if [[ ! $password ]]
then
    echo "Mission failed."
fi

## FIXME(v4): run echoes the full command line, so the plaintext password is
## printed to the terminal and exposed in the process list while it runs;
## pass the secret via stdin/env in v4.
run testsaslauthd -u "$ARG" -p "$password"
