#!/bin/bash

##
##   modules/ca/hooks/regenerate.sh — CA replication on regenerate.
##
##   Fired by "run_hook regenerate" (containers regenerate command, add-ve,
##   add-ve-user, add-network-ve, ...). Delegates to ca_sync (libs/netlib.sh):
##   a no-op message on the CA host, an rsync mirror of the CA host's
##   /etc/srvctl/CA tree onto this host otherwise.
##

ca_sync
