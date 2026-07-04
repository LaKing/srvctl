#!/bin/bash

#local zone services

run firewall-cmd --get-default-zone
run firewall-cmd --state
run firewall-cmd --zone="$zone" --list-services
run firewall-cmd --list-interfaces

interfaces="$(firewall-cmd --list-interfaces)"

for i in $interfaces
do
    run firewall-cmd --get-zone-of-interface="$i"
done

## firewall-cmd --zone=trusted --add-interface=10.50.0.x