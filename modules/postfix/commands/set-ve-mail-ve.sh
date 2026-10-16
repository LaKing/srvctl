#!/bin/bash

## @@@ set-ve-mail-ve VE [MAILVE|off]
## @en Hand the mail of a VE to another VE, MAILVE: it receives and sends for the VE's domains
## &en Inbound mail and IMAP/POP3/SMTP logins for the VE and its aliases go to MAILVE.
## &en MAILVE's postfix takes those domains as its own; addresses stay unchanged, info@VE is delivered as info@VE.
## &en Without MAILVE the current setting is shown. 'off' or 'none' gives the mail back to the VE.
## &en MAILVE must run on this host; the MX of the VE's domains stays mail.VE.

root_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   postfix/commands/set-ve-mail-ve.sh — set/clear the container field mail_ve.
##
##   Order matters: MAILVE accepts the domains first (regenerate_mail_ves),
##   only then does /etc/hosts point mail.VE at it. The other way round, mail
##   arriving in between is relayed by MAILVE back to the host (the host is in
##   its mynetworks) and loops.
##

argument container
C="$ARG"
[[ $(get container "$C" exist) == true ]] || { err "No such container: $C"; exit 22; }

if [[ -z $OPA ]]
then
    msg "Mail of $C is handled by $(get container "$C" mail_ve || echo "$C itself")"
    exit 0
fi

if [[ $OPA == off || $OPA == none ]]
then
    put container "$C" mail_ve > /dev/null
    datastore_push "put container $C mail_ve"
    regenerate_etc_hosts
    regenerate_mail_ves
    msg "Mail of $C is handled by $C again"
    exit 0
fi

target="$OPA"
[[ $target != "$C" ]] || { err "A VE cannot hand its mail to itself; use off"; exit 22; }
[[ $(get container "$target" exist) == true ]] || { err "No such container: $target"; exit 22; }
[[ $(get container "$target" host) == "$HOSTNAME" ]] || { err "$target does not run on $HOSTNAME"; exit 22; }
systemctl is-active --quiet "srvctl-nspawn@$target.service" || { err "$target is not running"; exit 22; }
[[ -f /srv/$target/rootfs/etc/postfix/main.cf ]] || { err "$target has no postfix"; exit 22; }

old="$(get container "$C" mail_ve)"
put container "$C" mail_ve "$target" > /dev/null
if ! regenerate_mail_ves || ! grep -q " OK$" "/srv/$target/rootfs$SC_MAIL_VE_DOMAINS"
then
    ## Undo, or the next regenerate would point mail.VE at a target that rejects it.
    if [[ -n $old ]]; then put container "$C" mail_ve "$old" > /dev/null; else put container "$C" mail_ve > /dev/null; fi
    err "$target postfix could not be configured; mail of $C stays where it was"
    exit 1
fi
datastore_push "put container $C mail_ve $target"
regenerate_etc_hosts
msg "Mail of $C is handled by $target"
ntc "Deferred mail for $C is retried at the next queue run; 'postqueue -f' sends it now"
