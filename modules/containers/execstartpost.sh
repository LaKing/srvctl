#!/bin/bash

## this script can run outside of srvctl! It will get invoked over systemd units
# shellcheck disable=SC2034
C="$1"

#/usr/bin/srvctl put container "$C" started true

interface="$(/usr/bin/srvctl get container "$C" interface)"
if ip link set dev "$interface" up
then
    echo "[ OK ] ip link set dev $interface up"
else
    echo "[FAIL] ip link set dev $interface up"
fi

bridge="$(/usr/bin/srvctl get container "$C" br)"
if brctl addif "$bridge" "$interface"
then
    echo "[ OK ] brctl addif $bridge $interface"
else
    echo "[FAIL] brctl addif $bridge $interface"
fi