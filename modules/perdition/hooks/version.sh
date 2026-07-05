#!/bin/bash

##
##   modules/perdition/hooks/version.sh — report installed version.
##
##   Would print the installed perdition package version via
##   msg_version_installed (srvctl module lib). Dead hook: nothing in
##   the tree calls run_hook/run_hooks with 'version', and 'sc version'
##   (modules/srvctl/commands/version.sh) only queries postfix and
##   nodejs. The same dead pattern exists in the named, opendkim,
##   postfix and saslauthd modules.
##

## FIXME(v4): low — dead hook, never executed; either wire a version
## hook into the version command or drop this file.
msg_version_installed perdition
