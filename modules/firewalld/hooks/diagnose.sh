#!/bin/bash

##
##   modules/firewalld/hooks/diagnose.sh — firewall state report.
##
##   Runs via 'run_hooks diagnose' at the end of 'sc diagnose'
##   (modules/srvctl/commands/diagnose.sh). Read-only: prints the
##   default zone, firewalld state, the services of $zone, the
##   interfaces, and the zone of each interface.
##

run firewall-cmd --get-default-zone
run firewall-cmd --state

## FIXME(v4): $zone leaks in from the parent diagnose command, which sets
## it only when /usr/sbin/firewalld exists — otherwise this runs
## 'firewall-cmd --zone= --list-services' and prints errors; the parent
## also already printed the zone/services/interfaces, so this section
## appears twice. Compute the zone here or drop the hook.
# shellcheck disable=SC2154 ## parent-scoped
run firewall-cmd --zone="$zone" --list-services
run firewall-cmd --list-interfaces

interfaces="$(firewall-cmd --list-interfaces)"

for i in $interfaces
do
    run firewall-cmd --get-zone-of-interface="$i"
done

## firewall-cmd --zone=trusted --add-interface=10.50.0.x
