#!/bin/bash

##
##   modules/ntp/hooks/update-install-host.sh — host time daemon setup.
##
##   Fired by "run_hooks update-install-host" during "sc update-install"
##   on a host only (nspawn containers share the host clock, so there is
##   no update-install-ve counterpart). Installs the ntpsec package
##   (sc_install, srvctl module's fedoralib.sh: dnf -y -q install), then
##   enables and starts ntpd.service via run (lablib.sh). The last
##   command's exit status becomes the sourced hook's return value.
##

## FIXME(v4): no idempotence guard — every update-install re-runs dnf
## install, and an offline host fails here even with ntpd already running.
sc_install ntpsec

## FIXME(v4): chronyd (Fedora's default time daemon) is never disabled;
## it stays enabled and races the also-enabled ntpd at next boot.
run systemctl enable ntpd
## FIXME(v4): if this start (or the install above) fails, the hook's
## nonzero status hits run_hook's exif and aborts the whole update-install
## run, skipping all alphabetically-later modules' hooks — and silently,
## since run suppresses its eyif warning for systemctl commands.
run systemctl start ntpd
