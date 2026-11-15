#!/bin/bash

##
##   usersonhost/hooks/prune.sh — unmount and remove the shares of removed
##   containers and of users taken off a container (see libs/prunelib.sh).
##   Runs before every regenerate and after remove-ve / destroy-ve.
##

sc_is_root || return 0

prune_user_shares

return 0
