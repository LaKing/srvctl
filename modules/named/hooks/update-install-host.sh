#!/bin/bash

##
##   modules/named/hooks/update-install-host.sh — (re)install BIND.
##
##   Runs via 'run_hooks update-install-host' from the srvctl module's
##   update-install command. Calls install_named (libs/install.sh), which
##   installs the bind packages, rewrites /etc/named.conf and the
##   /var/named skeleton, enables the named service and opens the dns
##   firewall service. Note: /etc/named.conf is overwritten on every run.
##

install_named
