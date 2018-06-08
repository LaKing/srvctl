#!/bin/bash


local zone services

zone=$(firewall-cmd --get-default-zone)
services="services: $(firewall-cmd --zone="$zone" --list-services) ."

msg "Firewall $(firewall-cmd --state) - default zone: $zone"
echo "$services"
echo ''

interfaces=$(firewall-cmd --list-interfaces)

for i in $interfaces
do
    echo "$i - $(firewall-cmd --get-zone-of-interface="$i")"
    echo ''
done
