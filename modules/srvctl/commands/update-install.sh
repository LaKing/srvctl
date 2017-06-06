#!/bin/bash

root_only #|| return 244

## @en Run the installation/update script.
## &en Update/Install all components
## &en On host systems install the containerfarm

if [[ ! -f /etc/srvctl/debug.conf ]]
then
    echo "DEBUG=true" > /etc/srvctl/debug.conf
    msg "Debugging turned on - /etc/srvctl/debug.conf"
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
    rm -fr /etc/srvctl/modules.conf
    exit
fi

## just some default
git config --global user.name "srvctl"
git config --global user.email "srvctl@$HOSTNAME"

msg "Calling update-install hooks."
run_hooks update-install

make_commands_spec

set_permissions
msg "update-install complete"
echo ""
