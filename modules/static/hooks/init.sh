#!/bin/bash

##
##   modules/static/hooks/init.sh — ensure the static storage tree.
##
##   Runs via 'run_hook init' (init.sh) on every srvctl invocation on
##   enabled hosts. Returns 0 unconditionally, so a failed mkdir never
##   aborts the run.
##

mkdir -p /var/srvctl3/storage

return 0
