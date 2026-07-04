#!/bin/bash

## this script can run outside of srvctl! It will get invoked over systemd units
# shellcheck disable=SC2034
C="$1"

echo "[execstartpost] $C"

if [[ ! -d /srv/"$C" ]]
then
    echo "Machine folder not found."
    exit 14
fi

if [[ -f /srv/"$C"/ethernet.sh ]]
then
	echo "[execstartpost] Calling /srv/"$C"/ethernet.sh"
    /bin/bash /srv/"$C"/ethernet.sh
fi

sleep 3

#ip="$(machinectl status "$C" | head -n 6 | tail -n 1 |  sed 's/^.*: //')"
ip="$(machinectl status "$C"| head -n 8 | grep Address |  sed 's/^.*: //')"


if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
    echo "[execstartpost] IP for $C is $ip"
    #/usr/bin/srvctl put container "$C" ip "$ip"
else
    echo "[execstartpost] No IP address for $C (result $ip)"
fi

#/usr/bin/srvctl put container "$C" started true

exit 0