#!/bin/bash

## @@@ add-zerotier NETWORKID
## @en Install ZeroTier and add a network
## &en You can access the container over your ZeroTier network

## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4



ve_only
root_only

ID="$ARG"

if [[ $ARG ]]
then
	msg "Install ZeroTier with network $ARG"
else
	if [[ -f /var/srvctl3/share/common/zerotier-one/devicemap ]]
	then
    	hostprefix="${HOSTNAME%%-*}"
		ID=$(awk -F= -v name="zt-$hostprefix" '$2 == name { print $1; exit }' "/var/srvctl3/share/common/zerotier-one/devicemap")

		if [[ -z "$ID" ]]; then
    		err "No ZeroTier network found for hostname prefix: $hostprefix"
    		exit 1
		fi
        
        msg "ZeroTier Host: $hostprefix Network ID: $ID"
	else
		err "No network specified"
		exit
    fi
fi

#msg "Set the default zone to trusted."
#firewall-cmd --set-default-zone=trusted

curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' | gpg --import && \  
if z=$(curl -s 'https://install.zerotier.com/' | gpg); then echo "$z" | bash; fi

if [[ -f /var/srvctl3/share/common/zerotier-one/devicemap ]]
then
	msg "ZeroTier can use a devicemap."
	ln -sfn /var/srvctl3/share/common/zerotier-one/devicemap /var/lib/zerotier-one/devicemap
    cat /var/lib/zerotier-one/devicemap
fi

run dnf -y update zerotier-one
run zerotier-cli info

if [[ $ARG ]]
then
	msg "Keeping ZeroTier ID's"
else
	msg "Resetting Zerotier ID"
	run systemctl stop zerotier-one
	run rm -rf /var/lib/zerotier-one/identity.secret /var/lib/zerotier-one/identity.public
	run rm -rf /var/lib/zerotier-one/peers.d
	run systemctl start zerotier-one
fi

run zerotier-cli join $ID


if [[ -f /var/lib/zerotier-one/devicemap ]]
then
	sleep 3
	if grep -q "$ID" /var/lib/zerotier-one/devicemap
	then
    	interface_name=$(cat /var/lib/zerotier-one/devicemap | grep "$ID" | cut -d'=' -f2)
		msg "Setting up firewalld to trust $interface_name"
    	firewall-cmd --zone=trusted --add-interface=$interface_name --permanent
    	firewall-cmd --reload
	else
		ntc "ID not found in devicemap, zt-interface is not trusted."
	fi
fi

run firewall-cmd --zone=trusted --list-interfaces

## testing Multicast UDP, for Xilica Xtouch
## sudo tcpdump -i br0 -A | grep -B 1 HeartBeat

## firewall-cmd --zone=trusted --add-interface=zt-zeroctl --permanent && firewall-cmd --reload
## firewall-cmd --zone=trusted --add-interface=host0 --permanent && firewall-cmd --reload
## firewall-cmd --zone=trusted --list-interfaces
