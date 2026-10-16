#!/bin/bash

##
##   modules/opendkim/hooks/update-install-host.sh — install opendkim.
##
##   Runs via 'run_hooks update-install-host' from 'sc update-install'
##   (modules/srvctl/commands/update-install.sh). Installs the opendkim
##   and opendkim-tools packages, writes /etc/opendkim.conf (sign+verify
##   milter on 127.0.0.1:8891, consumed by the postfix module's host
##   main.cf; inbound results labelled with the private authserv-id of
##   the postfix module's libs/mailauthlib.sh), and enables/starts
##   opendkim.service via add_service. The
##   key and table files the config points at under /var/opendkim are
##   produced later by the regenerate hook (libs/opendkimlib.sh).
##

msg "Install opendkim, to sign e-mails."

sc_install opendkim
sc_install opendkim-tools

## Overwrites /etc/opendkim.conf unconditionally (libs/opendkimlib.sh).
## MAILAUTH_INTERNAL_ID comes from the postfix module's libs/mailauthlib.sh,
## loaded together with this module (same containers condition).
if [[ -z ${MAILAUTH_INTERNAL_ID:-} ]]
then
    err "MAILAUTH_INTERNAL_ID is not set (postfix libs/mailauthlib.sh not loaded), using srvctl-internal.invalid"
fi
opendkim_conf "${MAILAUTH_INTERNAL_ID:-srvctl-internal.invalid}" > /etc/opendkim.conf

#regenerate_opendkim
## FIXME(v4): low — regenerate_opendkim above is commented out, but
## add_service below enables and restarts the daemon while the
## /var/opendkim/{KeyTable,SigningTable,TrustedHosts} files referenced by
## /etc/opendkim.conf do not exist yet on a fresh host; opendkim.service
## fails to start until the first 'sc regenerate', and outgoing mail is
## meanwhile unsigned (postfix milter_default_action accept).

add_service opendkim
