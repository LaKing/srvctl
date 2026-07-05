#!/bin/bash

##
##   modules/perdition/hooks/mkrootfs_fedora.sh — mail rootfs firewall.
##
##   Sourced by 'run_hooks mkrootfs_fedora' from the containers
##   module's rootfs build. For the 'mail' rootfs template only, opens
##   imap, imaps and pop3s inside the container image being built
##   (chroot firewall-offline-cmd), so per-domain mail containers
##   accept the proxied dovecot connections.
##

# shellcheck disable=SC2154
if [[ "$rootfs_name" == "mail" ]]
then
    firewalld_offline_add_service imap
    firewalld_offline_add_service imaps
    firewalld_offline_add_service pop3s
fi
