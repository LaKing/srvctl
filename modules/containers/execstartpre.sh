#!/bin/bash

## this script can run outside of srvctl! It will get invoked over systemd units
# shellcheck disable=SC2034
C="$1"
rootfs="/srv/$C/rootfs"

mkdir -p /var/srvctl3/share/containers/"$C"

## if containers are rsync-ed across hosts, ssh keys change users from ssh_keys to dovenull between fedora 27/28 and possibly others
## fedora 28 uses uid 996 while previous versions used 995
#chown 0:996 "$rootfs"/etc/ssh/ssh_host_ecdsa_key
#chown 0:996 "$rootfs"/etc/ssh/ssh_host_ed25519_key
#chown 0:996 "$rootfs"/etc/ssh/ssh_host_rsa_key
## an additional chmod, so that only root is relevant
#chmod 600 "$rootfs"/etc/ssh/ssh_host_ecdsa_key
#chmod 600 "$rootfs"/etc/ssh/ssh_host_ed25519_key
#chmod 600 "$rootfs"/etc/ssh/ssh_host_rsa_key

if [[ -f /srv/$C/local.nspawn ]]
then
    ## override the container nspawn file with the local nspawn file.
    cat "/srv/$C/local.nspawn" >  "/srv/$C/$C.nspawn"
else
    ## automatic config via srvctl
    echo "create_nspawn_container_settings"
    bash /bin/srvctl exec-function create_nspawn_container_settings "$C" || exit 11
fi

if [[ -f /srv/$C/hosts ]] && [[ -f /srv/$C/network/80-container-host0.network ]] && [[ -f /srv/$C/$C.nspawn ]]
then
    exit 0
else
    [[ -f /srv/$C/hosts ]] || echo "missing hosts file"
    [[ -f /srv/$C/network/80-container-host0.network ]] || echo "missing 80-container-host0.network file"
    [[ -f /srv/$C/$C.nspawn ]] || echo "missing npsawn file"
    echo "missing config files for nspawn detected in execstartpre for $C"
    exit 15
fi

## we need to restart systemd due to https://github.com/systemd/systemd/issues/13530
systemctl restart systemd-networkd