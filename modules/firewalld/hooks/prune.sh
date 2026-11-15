#!/bin/bash

##
##   firewalld/hooks/prune.sh — close the forwarded ports of removed containers
##   (see libs/prunelib.sh). Runs before every regenerate and after remove-ve /
##   destroy-ve.
##

$SC_UID0 || return 0

prune_firewalld_ports

return 0
