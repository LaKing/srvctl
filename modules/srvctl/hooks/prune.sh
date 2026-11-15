#!/bin/bash

##
##   srvctl/hooks/prune.sh — remove what removed modules left on this host.
##
##   The prune hook runs before the regenerate hooks of every regenerate and
##   after remove-ve / destroy-ve. Each module removes its own leftovers in its
##   hooks/prune.sh through the prune function (lablib.sh). A prune hook ends
##   with 'return 0': a leftover that could not be removed is reported, it must
##   not stop the run.
##

## uid 0 and not sc_is_root: an owner who removed his container through sudo
## runs the prune hooks too.
$SC_UID0 || return 0

prune_retired

return 0
