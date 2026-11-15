#!/bin/bash

##
##   datastore/hooks/prune.sh — remove the v3 single-file datastore once the
##   per-record store is authoritative (see libs/prunelib.sh). Runs before
##   every regenerate.
##

sc_is_root || return 0

prune_monolithic_datastore

return 0
