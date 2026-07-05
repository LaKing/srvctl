#!/bin/bash

## @@@ update-ve VE
## @en Update container operating system
## &en The distro will be update with it's package manager.


hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container-name
authorize

##
##   containers/commands/update-ve.sh — STUB: distro upgrade of a
##   container rootfs. Unimplemented; the commented dnf lines sketch the
##   intended offline-upgrade approach.
##
##   FIXME(v4): stops the container's unit and then only prints
##   "Feature unimplemented" — the container is left stopped; either
##   implement the upgrade or drop the command.
##

C="$ARG"

if [[ -d /srv/$C/rootfs ]]
then
    service_action "srvctl-nspawn@$C.service" stop
    #dnf --use-host-config --releasever=33 --installroot "/srv/$C/rootfs" -y update --refresh

	# shellcheck disable=SC1091 ## runtime-path
	TARGET_RELEASE=$(source /etc/os-release && echo "$VERSION_ID")
	ntc "Upgrade to $TARGET_RELEASE"

	err "Feature unimplemented"

	#dnf --use-host-config --installroot "/srv/$C/rootfs" -y --nogpgcheck offline-upgrade download --releasever="$RELEASE_ID"

else
   	err "Container rootfs does not exist."
fi
