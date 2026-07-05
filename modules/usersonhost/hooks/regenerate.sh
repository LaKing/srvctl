#!/bin/bash

##
##   modules/usersonhost/hooks/regenerate.sh — user reconciliation on
##   regenerate.
##
##   Fired by "run_hook regenerate" from modules/containers/commands/
##   regenerate.sh. Delegates to userscfg (libs/bashlib.sh), i.e. runs
##   main.js with no arguments: for every user in the datastore it
##   ensures the system account, password (+datastore .password/.hash),
##   ssh keys, reseller key links, client p12 certificate and the
##   per-container bindfs share mounts under the user's home.
##

userscfg
