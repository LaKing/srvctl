#!/bin/bash

##
##   modules/opendkim/hooks/regenerate.sh — refresh DKIM keys and tables.
##
##   Runs via 'run_hook regenerate' from 'sc regenerate'
##   (modules/containers/commands/regenerate.sh) and after add-ve /
##   add-ve-user / add-network-ve / add-codepad. Calls
##   regenerate_opendkim (libs/opendkimlib.sh): opendkim.js generates
##   missing per-domain signing keys, syncs them into the datastore,
##   publishes the public keys into containers.json (consumed by the
##   named module for DNS TXT records) and rebuilds TrustedHosts /
##   KeyTable / SigningTable; the datastore folder is then mirrored to
##   /var/opendkim and opendkim.service is restarted when anything
##   changed.
##

regenerate_opendkim

## Hosts that only run regenerate keep an /etc/opendkim.conf from an old
## update-install; this adds the inbound verification keys to it.
regenerate_opendkim_conf "${MAILAUTH_INTERNAL_ID:-srvctl-internal.invalid}"
