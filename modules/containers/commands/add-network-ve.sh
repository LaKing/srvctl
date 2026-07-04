#!/bin/bash

## @@@ add-network-ve NAME BRIDGE
## @en Add a VE for a application in a container on br-BRIDGE.
## &en Networking will be based on a DHCP client

## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

argument container-name
authorize
sudomize

if [[ ! -f /etc/systemd/network/br-"$OPA".network ]]
then
    err "No such bridge: br-$OPA"
    echo /etc/systemd/network/br-*.network
    exit
fi

N="${ARG%%.*}"

#if [ ${#N} -ge 11 ] 
#then
#    err "Subdomain name is too long"
#    exit
#fi

C="$ARG"
br=br-"$OPA"

#systemctl restart systemd-networkd

if [[ -f /srv/$C/rootfs/etc/os-release ]]
then
	err "Container exists"
    cat "/srv/$C/rootfs/etc/os-release"
else
    add_ve fedora "$C" "$br"
    #sleep 3
    #run machinectl -q --no-pager shell $C /bin/bash/ -c 'hostname --all-ip-addresses'
    #ip="$(machinectl -q --no-pager shell $C /bin/bash/ -c 'hostname --all-ip-addresses')"
    #msg "IP is $ip"
    #put container "$C" ip "$ip"
    run_hook add-ve
    run_hook add_ve_fedora
    run_hook regenerate
fi

#ssh "$C" bash /var/srvctl3/share/common/install/crossover.sh

#msg "Copy the crossover files"
#cp -pur /var/srvctl3/share/common/crossover/.cxoffice /srv/"$C"/rootfs/home/x
#ln -s /var/srvctl3/share/common/crossover/license.sig /srv/"$C"/rootfs/opt/cxoffice/etc/license.sig
#ln -s /var/srvctl3/share/common/crossover/license.txt /srv/"$C"/rootfs/opt/cxoffice/etc/license.txt

#msg "please enter the password for your VNC server instance"
#ssh x@"$C" vncserver

#msg "Setting up vncserver"
#vnc_setup "$C" /opt/cxoffice/bin/crossover

#We are using the following TCP/UDP ports.
#10001 - TCP control port.
#10002 - UDP heart beat broadcast port
#10003 - UDP data change update port
#10006 - UDP meter data update port
#10007 - TCP 3rd party control port
#10008 - UDP 3rd party data update port

## DISABLE FIREWALL PORT 5901 !!!
##?

ssh "$C" "firewall-cmd --zone=trusted --add-interface=host0 --permanent && firewall-cmd --reload"

msg Done
