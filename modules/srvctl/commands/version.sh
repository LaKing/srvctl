#!/bin/bash

## @@@ version
## @en List software versions installed.
## &en Contact the package manager, and query important packages
## &en

##
##   Print installed package versions via dnf (msg_version_installed,
##   libs/fedoralib.sh).
##

msg "-- software-versions --"

msg_version_installed postfix
msg_version_installed nodejs

## FIXME(v4): no 'run_hook version' here (or anywhere), so the
## hooks/version.sh files shipped by named, postfix, perdition and opendkim
## are dead code and 'sc version' only reports the two packages above.
## Adding the hook call would change output — left for v4.
