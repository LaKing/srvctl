#!/bin/bash

##
##   containers/hooks/prune.sh — remove what removed containers left behind
##   (see libs/prunelib.sh). Runs before every regenerate and after
##   remove-ve / destroy-ve, for root and for an owner who removed his
##   container through sudo, hence the uid test and not sc_is_root.
##

$SC_UID0 || return 0

prune_container_leftovers

return 0
