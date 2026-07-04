#!/bin/bash

## @@@ update-ve VE
## @en Update container operating system
## &en The distro will be update with it's package manager.


hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container-name
authorize
    
C="$ARG"
    
if [[ -d /srv/$C/rootfs ]]
then
    service_action "srvctl-nspawn@$C.service" stop
    #dnf --use-host-config --releasever=33 --installroot "/srv/$C/rootfs" -y update --refresh


	TARGET_RELEASE=$(source /etc/os-release && echo "$VERSION_ID")
	ntc "Upgrade to $TARGET_RELEASE"

	err "Feuture unimplemented"
    
	#dnf --use-host-config --installroot "/srv/$C/rootfs" -y --nogpgcheck offline-upgrade download --releasever="$RELEASE_ID"

else
   	err "Container rootfs does not exist."
fi
