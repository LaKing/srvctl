#!/bin/bash

###
msg "Containerfarm host installation"

## this option allows machinectl to see our custom machines
#if [[ ! -d /var/lib/containers ]] && [[ ! -f /var/lib/containers ]]
#then
#    run ln -s /srv /var/lib/container
#fi


sc_install systemd-container

create_srvctl_nspawn_service

run systemctl enable machines.target


regenerate_ssh_config
