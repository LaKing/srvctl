#!/bin/bash

##
##   usersonhost/hooks/prune.sh — unmount and remove the shares of removed
##   containers and of users taken off a container (see libs/prunelib.sh).
##   Runs before every regenerate and after remove-ve / destroy-ve.
##

$SC_UID0 || return 0

prune_user_shares

return 0
