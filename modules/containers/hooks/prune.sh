#!/bin/bash

##
##   containers/hooks/prune.sh — remove what removed containers left behind
##   (see libs/prunelib.sh). Runs before every regenerate and after
##   remove-ve / destroy-ve.
##

prune_container_leftovers

return 0
