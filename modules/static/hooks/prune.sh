#!/bin/bash

##
##   static/hooks/prune.sh — remove the docroots of removed containers (see
##   libs/prunelib.sh). Runs before every regenerate and after remove-ve /
##   destroy-ve.
##

$SC_UID0 || return 0

prune_static_docroots

return 0
