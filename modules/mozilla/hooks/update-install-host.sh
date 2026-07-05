#!/bin/bash

##
##   modules/mozilla/hooks/update-install-host.sh — install the Thunderbird
##   mail-autoconfig service on the host.
##
##   Runs via 'run_hooks update-install-host' during 'sc update-install'
##   (modules/srvctl/commands/update-install.sh). Calls
##   install_mozilla_autoconfig (libs/install.sh), which writes and
##   enables/starts the mozilla-autoconfig.service systemd unit serving
##   the mail autoconfig XML on port 1029 (consumed by haproxy).
##   Install-only: there is no regenerate/remove/diagnose counterpart.
##

[[ $SRVCTL ]] || exit 4


install_mozilla_autoconfig
