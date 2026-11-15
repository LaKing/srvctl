#!/bin/bash

##
##   static/hooks/prune.sh — remove the docroots of removed containers (see
##   libs/prunelib.sh). Runs before every regenerate and after remove-ve /
##   destroy-ve.
##

sc_is_root || return 0

prune_static_docroots

return 0
