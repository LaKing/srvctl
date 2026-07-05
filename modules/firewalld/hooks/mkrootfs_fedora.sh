#!/bin/bash

##
##   modules/firewalld/hooks/mkrootfs_fedora.sh — template default ports.
##
##   Runs via 'run_hooks mkrootfs_fedora' while the containers module
##   builds the fedora rootfs template (modules/containers/libs/
##   mkrootfs_fedora.sh). Bakes the srvctl default web and mail ports
##   into the template via firewalld_offline_add_service (chroot +
##   firewall-offline-cmd), so every container cloned from it starts
##   with them open.
##

## rootfs_name comes from the parent calling the hook mkrootfslib
# shellcheck disable=SC2154
if [[ "$rootfs_name" == "fedora" ]]
then
    ## global http and https
    firewalld_offline_add_service http tcp 80
    firewalld_offline_add_service https tcp 443

    ## additional http and https
    firewalld_offline_add_service http8080 tcp 8080
    firewalld_offline_add_service https8443 tcp 8443

    ## elasticsearch
    firewalld_offline_add_service https9200 tcp 9200

    ## mail ports
    ## FIXME(v4): baked into every fedora template regardless of role — a
    ## commented-out conditional for a separate 'mail' rootfs used to gate
    ## these; move them to the mail modules.
    firewalld_offline_add_service imap tcp 143
    firewalld_offline_add_service imaps tcp 993
    firewalld_offline_add_service pop3s tcp 995
    firewalld_offline_add_service smtp tcp 25
    firewalld_offline_add_service smtps tcp 465
fi
