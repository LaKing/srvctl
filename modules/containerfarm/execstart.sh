#!/bin/bash

## this script can run outside of srvctl! It will get invoked over systemd units

C="$1"
bridge="$(cat "/srv/$C/bridge")"


/usr/bin/systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest --network-bridge="$bridge" -U --settings=override --machine="$C" -D "/srv/$C/rootfs"
