#!/bin/bash

##
##   firewalld/hooks/prune.sh — close the forwarded ports of removed containers
##   (see libs/prunelib.sh). Runs before every regenerate and after remove-ve /
##   destroy-ve.
##

sc_is_root || return 0

prune_firewalld_ports

return 0
