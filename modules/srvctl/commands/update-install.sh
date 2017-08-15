#!/bin/bash

## @@@ update-install [HOSTNAME]
## @en Run the installation/update script.
## &en Update/Install all components
## &en On host systems install the containerfarm

root_only

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
    
    if [[ $ARG ]]
    then
        msg "setting hostname as $ARG"
        echo "$ARG" > /etc/hostname
    else
        msg "please set a hostname"
        mcedit /etc/hostname
        cat /etc/hostname
    fi
    
    msg "after setting a hostname, a reboot is required"
    rm -fr /var/local/srvctl/modules.conf
    exit 5
fi

## just some default
git config --global user.name "srvctl"
git config --global user.email "srvctl@$HOSTNAME"

if $SC_USE_CONTAINERS
then
    mkdir -p /var/srvctl3/ssh
    mkdir -p ~/.ssh
    for host in $(cfg cluster host_list)
    do
        msg "ssh-keyscan $host"
        ssh-keyscan "$host" >> ~/.ssh/known_hosts
        #ssh-keyscan -t rsa "$host" >> /var/srvctl3/ssh/known_hosts
    done
fi

msg "Calling update-install hooks."
run_hooks update-install

make_commands_spec

set_permissions
msg "update-install complete"
echo ""
