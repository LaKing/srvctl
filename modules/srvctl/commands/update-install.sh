#!/bin/bash

root_only #|| return 244

## @en Run the installation/update script.
## &en Update/Install all components
## &en On host systems install the containerfarm

if [[ ! -f /etc/srvctl/debug.conf ]]
then
    echo "DEBUG=false" > /etc/srvctl/debug.conf
fi


sc_update

## disable selinux
msg 'disabling SELinux'
echo 'SELINUX=disabled' > /etc/selinux/config
## TODO enable it when we are there

## install if we dont have
[[ -f /bin/mc ]] || sc_install mc
[[ -f /bin/node ]] || sc_install nodejs
[[ -f /bin/git ]] || sc_install git

if [[ $HOSTNAME == localhost.localdomain ]]
then
    msg "please set a hostname"
    mcedit /etc/hostname
    cat /etc/hostname
    msg "after setting a hostname, a reboot is required"
    exit
fi

## just some default
git config --global user.name "srvctl"
git config --global user.email "srvctl@$HOSTNAME"


if [[ -d /etc/srvctl/data ]]
then
    msg "Found /etc/srvctl/data dir."
else
    msg "/etc/srvctl/data directory not found. It is recommended to have such a folder prepared."
    msg "Creating Empty database."
fi

init_datastore

msg "Writing host.conf"
out host "$HOSTNAME" > /etc/srvctl/host.conf
source /etc/srvctl/host.conf

regenerate_etc_hosts
networkd_configuration

msg "Calling update-install hooks."
run_hooks update-install



datastore_push

msg "update-install complete"
echo ""
