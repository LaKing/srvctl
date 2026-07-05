#!/bin/bash

##
##   letsencrypt/hooks/update-install-host.sh
##
##   Sourced via 'run_hooks update-install-host' from 'srvctl update-install'
##   (modules/srvctl/commands/update-install.sh). Installs certbot, the acme
##   user and /var/acme webroot, /etc/letsencrypt/cli.ini, the vendored CA
##   and the acme-server.service unit, then enables and starts the service
##   (install_acme, libs/letsencryptlib.sh).
##
##   Note: the certificates module's update-install-host hook also calls
##   install_acme, so it runs twice per update-install (see the FIXME
##   there); re-runs are harmless apart from useradd stderr noise.
##

[[ $SRVCTL ]] || exit 4

install_acme
