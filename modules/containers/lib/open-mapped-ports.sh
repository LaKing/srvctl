#!/bin/bash

## Runs on the HOST as a transient unit, started by execstartpost.sh after every
## container start: 'open-mapped-ports.sh C'. Outside srvctl, like its caller.
##
## The host forwards a container's mapped_ports (sc datastore, the Port= lines of
## /srv/C/C.nspawn), but the base image enables the container's own firewalld with
## only the standard web and mail ports (firewalld/hooks/mkrootfs_fedora.sh), so a
## forwarded port was refused inside (seen on p2: mail.printhub.hu's 2993 and 1465
## after rebuild-ve). The container-side ports are added there permanently, by the
## container's own firewall-cmd: its files keep the container's owners.
## Not in execstartpost itself: firewalld starts some seconds into the boot, and
## a waiting ExecStartPost would hold the unit in "activating".

C="$1"
SC_PORTS_SRV="${SC_PORTS_SRV:-/srv}" SC_PORTS_WAIT="${SC_PORTS_WAIT:-60}" ## test seams
nspawn="$SC_PORTS_SRV/$C/$C.nspawn"

in_ve() { systemd-run -q -M "$C" --pipe --wait "$@" 2> /dev/null; }

## Port=proto:host:container, or Port=proto:port for the same port on both sides
mapfile -t ports < <(sed -nE 's/^Port=(tcp|udp):([0-9]+)(:([0-9]+))?$/\1 \2 \4/p' "$nspawn" 2> /dev/null | awk '{print ($3 == "" ? $2 : $3) "/" $1}' | sort -u)
((${#ports[@]})) || exit 0

for ((i = 0; i < SC_PORTS_WAIT; i++))
do
    in_ve firewall-cmd --state > /dev/null && break
    ## no firewalld in this container (or not enabled): nothing filters the ports
    ((i > 5)) && ! in_ve systemctl is-enabled -q firewalld && exit 0
    sleep 1
done
((i < SC_PORTS_WAIT)) || { echo "[open-mapped-ports] $C: firewalld did not come up, ports not checked: ${ports[*]}"; exit 1; }

added=()
for p in "${ports[@]}"
do
    [[ $(in_ve firewall-cmd --permanent --query-port="$p") == yes ]] && continue
    in_ve firewall-cmd --permanent --add-port="$p" > /dev/null && added+=("$p")
done
((${#added[@]})) || exit 0
in_ve firewall-cmd --reload > /dev/null
echo "[open-mapped-ports] $C: opened in the container's firewalld: ${added[*]}"
