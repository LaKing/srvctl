#!/bin/bash

##
##   containers/execstoppost.sh — ExecStopPost of srvctl-nspawn@.service.
##
##   NOT a srvctl hook: systemd runs it as 'execstoppost.sh %i' outside
##   the srvctl environment after the container stops. Intentionally a
##   no-op placeholder (a datastore 'started false' write and a machinectl
##   terminate used to live here); kept because the installed unit
##   template references this path.
##

## this script can run outside of srvctl! It will get invoked over systemd units
# shellcheck disable=SC2034
C="$1"