#!/bin/bash

## @@@ add-network-ve NAME BRIDGE
## @en Add a VE for a application in a container on br-BRIDGE.
## &en Networking will be based on a DHCP client

## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/add-network-ve.sh — create a fedora container
##   attached to an existing custom bridge (br-BRIDGE, DHCP networking).
##
##   Requires /etc/systemd/network/br-$OPA.network to exist. Creates the
##   container via add_ve with the bridge argument, runs the add-ve /
##   add_ve_fedora / regenerate hooks, then trusts the container's host0
##   interface in its own firewalld over ssh. Historically this command
##   also provisioned crossover/vnc payloads; that code is gone.
##

argument container-name
authorize
sudomize

if [[ ! -f /etc/systemd/network/br-"$OPA".network ]]
then
    err "No such bridge: br-$OPA"
    echo /etc/systemd/network/br-*.network
    ## FIXME(v4): bare exit returns 0 — the missing-bridge failure reports success.
    exit
fi

C="$ARG"
br=br-"$OPA"

if [[ -f /srv/$C/rootfs/etc/os-release ]]
then
	err "Container exists"
    cat "/srv/$C/rootfs/etc/os-release"
else
    add_ve fedora "$C" "$br"
    run_hook add-ve
    run_hook add_ve_fedora
    run_hook regenerate
fi

## the bridge-attached interface is trusted inside the container
ssh "$C" "firewall-cmd --zone=trusted --add-interface=host0 --permanent && firewall-cmd --reload"

msg Done
