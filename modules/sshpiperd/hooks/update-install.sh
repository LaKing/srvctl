#!/bin/bash


msg "Installing sshpiper"

run adduser --system sshpiper
run mkdir -p /var/sshpiper

sc_install bindfs

mount_sshpiper

run mkdir -p /etc/sshpiper

if [[ ! -f /etc/sshpiper/ssh_host_rsa_key ]]
then
    msg "ssh-keygen sshpiper ssh_host_rsa_key"
    ssh-keygen -t rsa -f /etc/sshpiper/ssh_host_rsa_key -N ''
fi

run chown -R sshpiper:root /etc/sshpiper

## TODO remove after upgrade
rm -fr /usr/lib/systemd/system/sshpiperd.service

run cat "$SC_INSTALL_DIR/modules/sshpiperd/services/sshpiperd.service" > /etc/systemd/system/sshpiperd.service
run systemctl daemon-reload

firewalld_add_service sshpiperd tcp 2222
