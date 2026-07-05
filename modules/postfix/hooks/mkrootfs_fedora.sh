#!/bin/bash

##
##   modules/postfix/hooks/mkrootfs_fedora.sh — mail-image firewall ports.
##
##   Runs via 'run_hooks mkrootfs_fedora' during base-image builds
##   (modules/containers/libs/mkrootfs_fedora.sh); $rootfs_name and
##   $rootfs_base are set by the caller. Only for the "mail" image:
##   opens smtp (25/tcp) and smtps (465/tcp) inside the image via chroot
##   firewall-offline-cmd (modules/firewalld/libs/firewalldlib.sh).
##

## FIXME(v4): medium — smtps (465) is opened here, but conf/ve-master.cf
## (which would define the container-side submissions listener) is
## installed by nothing, so mail containers expose port 465 with no
## service listening on it.

# shellcheck disable=SC2154 ## caller-scope
if [[ "$rootfs_name" == "mail" ]]
then
    firewalld_offline_add_service smtp
    firewalld_offline_add_service smtps
fi
