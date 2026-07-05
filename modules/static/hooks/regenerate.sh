#!/bin/bash

##
##   modules/static/hooks/regenerate.sh — reseed static docroots.
##
##   Runs via 'run_hook regenerate' — fired by 'sc regenerate' and by the
##   container add commands (add-ve, add-ve-user, add-network-ve,
##   add-codepad). Announces the step, then regenerate_static_server
##   (libs/regenerate.sh) creates any missing per-container docroots
##   under /var/srvctl3/storage/static/.
##

msg "Regenerate static fileserver structure"
regenerate_static_server
