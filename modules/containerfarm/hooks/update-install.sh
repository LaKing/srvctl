#!/bin/bash

## srvctl3 sudo functions
sc_install sudo
echo '## srvctl v3 sudo file' > /etc/sudoers.d/srvctl
echo 'ALL ALL=(ALL) NOPASSWD: /usr/share/srvctl/srvctl.sh diagnose' >> /etc/sudoers.d/srvctl

###
msg "Containerfarm host installation"

## network configuration
#run systemctl is-active network
#run systemctl is-active NetworkManager

run systemctl enable systemd-networkd
run systemctl start systemd-networkd

msg "It is recommended to create systemd-networkd configurations for ethernet cards."
networkctl | grep ' en' | grep ether | grep routable | grep unmanaged

## Recommended way for DNS resolution with systemd
run rm -f /etc/resolv.conf
run ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
run systemctl enable systemd-resolved
run systemctl start systemd-resolved


###

## this option allows machinectl to see our custom machines
#if [[ ! -d /var/lib/containers ]] && [[ ! -f /var/lib/containers ]]
#then
#    run ln -s /srv /var/lib/container
#fi

## disable selinux
msg 'disabling SELinux'
echo 'SELINUX=disabled' > /etc/selinux/config
## TODO enable it when we are there

sc_install systemd-container

