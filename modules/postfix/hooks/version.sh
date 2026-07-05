#!/bin/bash

##
##   modules/postfix/hooks/version.sh — report installed version.
##
##   Would print the installed postfix package version via
##   msg_version_installed (srvctl module lib). Dead hook: nothing in the
##   tree calls run_hook/run_hooks with 'version'; 'sc version'
##   (modules/srvctl/commands/version.sh) hardcodes the same call instead.
##

## FIXME(v4): low — dead hook, never executed; either wire a version hook
## into the version command or drop this file.
msg_version_installed postfix
