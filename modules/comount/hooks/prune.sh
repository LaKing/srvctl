#!/bin/bash
[[ $SRVCTL ]] || exit 4

##
##   comount/hooks/prune.sh — remove the mount units of removed containers
##   (see libs/prunelib.sh). Runs before every regenerate and after remove-ve /
##   destroy-ve.
##

$SC_UID0 || return 0

prune_comount_units

return 0
