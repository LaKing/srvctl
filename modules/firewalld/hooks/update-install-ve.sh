#!/bin/bash

##
##   modules/firewalld/hooks/update-install-ve.sh — container firewall setup.
##
##   Runs via 'run_hooks update-install-ve' from 'sc update-install'
##   inside a container. Installs firewalld, enables and starts the
##   service, then runs the 'firewalld' hook point to open the default
##   ports.
##

## FIXME(v4): unconditional sc_install, but sc_install is only defined on
## Fedora (modules/srvctl/libs/fedoralib.sh); in a Debian/Ubuntu/Arch
## container this exits 127 ("command not found"), the firewall-cmd calls
## in the hooks below fail, and run_hook's exif aborts update-install.
sc_install firewalld

run systemctl enable firewalld
run systemctl start firewalld
run systemctl status firewalld --no-pager

run_hooks firewalld
