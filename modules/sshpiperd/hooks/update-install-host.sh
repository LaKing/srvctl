#!/bin/bash

##
##   modules/sshpiperd/hooks/update-install-host.sh — host provisioning.
##
##   Runs via 'run_hooks update-install-host' from 'sc update-install'
##   on a farm host. Creates the sshpiper system user, installs bindfs
##   and mounts the datastore users view on /var/sshpiper, generates the
##   daemon host key under /etc/sshpiper, deploys the vendored sshpiperd
##   binary to /bin/sshpiperd plus its systemd unit, and opens tcp/2222
##   in firewalld. The service itself is not enabled or started here.
##

msg "Installing sshpiper"

run adduser --system sshpiper
run mkdir -p /var/sshpiper

sc_install bindfs

mount_sshpiper

run mkdir -p /etc/sshpiper

## The filename says rsa but the key is ecdsa — misleading, yet
## load-bearing: the unit's --server_key and every port-2222 user's
## known_hosts pin this exact path and key, so never rename or
## regenerate it.
if [[ ! -f /etc/sshpiper/ssh_host_rsa_key ]]
then
    msg "ssh-keygen sshpiper ssh_host_rsa_key"
    ssh-keygen -t ecdsa -f /etc/sshpiper/ssh_host_rsa_key -N ''
fi

run chown -R sshpiper:root /etc/sshpiper

## TODO remove after upgrade
## FIXME(v4): legacy-unit cleanup still runs on every update-install.
rm -fr /usr/lib/systemd/system/sshpiperd.service

## FIXME(v4): the vendored binary is stale (banner 3.1.2.1, reads
## <user>/srvctl_id_rsa) while workingdir.go and the rest of srvctl use
## srvctl_id_ecdsa — upstream key mapping cannot succeed on a fresh host.
cp -a "$SC_INSTALL_DIR/modules/sshpiperd/sshpiperd" /bin/sshpiperd

## FIXME(v4): 'run' echoes the command line to stdout (lablib.sh), so the
## redirection prepends a colored prompt line to the installed unit file;
## plain 'cat' (or cp) would deploy the unit verbatim.
run cat "$SC_INSTALL_DIR/modules/sshpiperd/services/sshpiperd.service" > /etc/systemd/system/sshpiperd.service
run systemctl daemon-reload
## FIXME(v4): the unit is installed but never enabled or started; a fresh
## host leaves sshpiperd dead until an operator runs 'sc sshpiperd !'.

firewalld_add_service sshpiperd tcp 2222
