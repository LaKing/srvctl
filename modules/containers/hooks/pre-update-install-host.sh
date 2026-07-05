#!/bin/bash

##
##   containers/hooks/pre-update-install-host.sh — network prerequisites.
##
##   Runs before the update-install-host hooks: regenerates /etc/hosts
##   from the cluster datastore (libs/regenlib.sh) and applies the
##   systemd-networkd base configuration (networkd_configuration,
##   modules/srvctl) so container bridges can attach.
##

regenerate_etc_hosts
networkd_configuration
