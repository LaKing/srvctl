#!/bin/bash

## this script can run outside of srvctl! It will get invoked over systemd units
# shellcheck disable=SC2034
C="$1"

echo "execstartpost $C"

if [[ -f /srv/"$C"/ethernet.sh ]]
then
    /bin/bash /srv/"$C"/ethernet.sh
fi

sleep 3

ip="$(machinectl -q --no-pager shell $C /bin/bash/ -c 'hostname --all-ip-addresses')"
if [[ $ip ]]
then
    echo "IP for $C is $ip"
    /usr/bin/srvctl put container "$C" ip "$ip"
else
    echo "No IP address for $C"
fi

#/usr/bin/srvctl put container "$C" started true

exit 0