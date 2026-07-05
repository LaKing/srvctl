#!/bin/bash

##
##   modules/firewalld/hooks/update-install-host.sh — host firewall setup.
##
##   Runs via 'run_hooks update-install-host' from 'sc update-install'
##   (modules/srvctl/commands/update-install.sh) on a farm host.
##   Installs firewalld if missing, enables and starts the service, runs
##   the 'firewalld' hook point (this module's and other modules' port
##   declarations), then ensures IPv4 masquerade on the default zone —
##   permanent and runtime — which provides NAT for the 10.x container
##   network.
##

if [[ ! -f /usr/sbin/firewalld ]]
then
    sc_install firewalld
fi

run systemctl enable firewalld
run systemctl start firewalld
run systemctl status firewalld --no-pager

run_hooks firewalld

## masquerade: query permanent and runtime separately, add what is missing
if [[ "$(firewall-cmd --query-masquerade --permanent)" != yes ]]
then
    run firewall-cmd --add-masquerade --permanent
fi

if [[ "$(firewall-cmd --query-masquerade)" != yes ]]
then
    run firewall-cmd --add-masquerade
fi
