#!/bin/bash

##
##   modules/perdition/hooks/update-install-host.sh — host install hook.
##
##   Sourced by 'run_hooks update-install-host' from the update-install
##   command. Deliberately a no-op since the inline install code moved
##   to libs/install_perdition.sh and its call was commented out: the
##   module is half-abandoned in v3 and slated to be replaced by the
##   G9 mail proxy in v4.
##

## FIXME(v4): high — install_perdition has no caller anywhere, so a
## fresh host never gets the perdition package, certs, /var/perdition
## or the three units, yet the module stays active and its regenerate
## hook then aborts container provisioning (see hooks/regenerate.sh).
## Decide: re-enable the line below, or retire the module for G9.
#install_perdition
