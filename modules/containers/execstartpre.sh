#!/bin/bash

##
##   containers/execstartpre.sh — ExecStartPre of srvctl-nspawn@.service.
##
##   NOT a srvctl hook: systemd runs it as 'execstartpre.sh %i' outside
##   the srvctl environment, right before systemd-nspawn boots the
##   container. Ensures the per-container share directory exists and that
##   the nspawn config is fresh: /srv/$C/local.nspawn (manual override)
##   is copied verbatim over $C.nspawn, otherwise the config is rendered
##   from the datastore via 'srvctl exec-function
##   create_nspawn_container_config' (exit 11 aborts the unit start).
##   Exits 15 — also aborting the start — when the hosts file or the
##   nspawn file is still missing afterwards.
##
##   (Historic note: rsync-ed containers used to need ssh host key
##   chowns here, ssh_keys uid moved between fedora releases.)
##

## this script can run outside of srvctl! It will get invoked over systemd units
# shellcheck disable=SC2034
C="$1"
rootfs="/srv/$C/rootfs"

mkdir -p /var/srvctl3/share/containers/"$C"

if [[ -f /srv/$C/local.nspawn ]]
then
    ## override the container nspawn file with the local nspawn file.
    cat "/srv/$C/local.nspawn" >  "/srv/$C/$C.nspawn"
else
    ## automatic config via srvctl
    echo "[execstartpre] create_nspawn_container_config"
    bash /bin/srvctl exec-function create_nspawn_container_config "$C" || exit 11
fi

if [[ -f /srv/$C/hosts ]] && [[ -f /srv/$C/$C.nspawn ]]
then
    exit 0
else
    [[ -f /srv/$C/hosts ]] || echo "missing hosts file"
    [[ -f /srv/$C/$C.nspawn ]] || echo "missing npsawn file"
    echo "[execstartpre] missing config files for nspawn detected in execstartpre for $C"
    exit 15
fi

## we would need to restart systemd-networkd if custom interface would be used due to https://github.com/systemd/systemd/issues/13530
# systemctl restart systemd-networkd