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
##   KeyTable and the signing-entitlement tables (lib/entitlement.js); the
##   datastore folder is then mirrored to /var/opendkim and
##   opendkim.service is restarted when anything changed. Then
##   regenerate_opendkim_conf sets the signing-policy keys of
##   /etc/opendkim.conf and the Postfix settings they need (production
##   hosts never run update-install, so this is how they get them).
##

regenerate_opendkim
regenerate_opendkim_conf
