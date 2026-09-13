#!/bin/bash

##
##   codepad mkrootfs_fedora hook — sourced by run_hooks mkrootfs_fedora
##   at the end of every fedora-family rootfs build (containers module,
##   mkrootfs_fedora_base). Only acts on the codepad template: opens its
##   web and codepad ports with firewall-offline-cmd inside the chroot.
##   Service names become /etc/firewalld/services/*.xml in the template and
##   are load-bearing (firewalld_offline_add_service rechecks them by name).
##   They agree with the host names in hooks/firewalld.sh since the host's
##   9000 service was renamed http9000 -> https9000; the template always
##   used https9000.
##

## rootfs_name is a local of the calling mkrootfs_fedora_base, visible
## here because hooks are sourced
# shellcheck disable=SC2154
if [[ "$rootfs_name" == codepad ]]
then

    ## apply same as /modules/firewalld/hooks/mkrootfs_fedora.sh

    ## global http and https
    firewalld_offline_add_service http tcp 80
    firewalld_offline_add_service https tcp 443

    ## additional http and https
    firewalld_offline_add_service http8080 tcp 8080
    firewalld_offline_add_service https8443 tcp 8443

    ## elasticsearch
    firewalld_offline_add_service https9200 tcp 9200

    ## apply codepad extras
    firewalld_offline_add_service https9000 tcp 9000
    firewalld_offline_add_service https9001 tcp 9001
    firewalld_offline_add_service https9002 tcp 9002
fi
