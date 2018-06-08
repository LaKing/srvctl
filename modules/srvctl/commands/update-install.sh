#!/bin/bash

## @@@ update-install
## @en Run the installation/update script.
## &en Update/Install all components.
## &en On host systems install the containerfarm. and additionally use [HOSTNAME] as additional argument to select a host from a cluster.

root_only

sc_update

if ! $SC_USE_CONTAINERS
then
    ## this will be executed on containers
    run_hooks update-install-ve
    
    msg "$HOSTNAME update-install complete"
    exit 0
fi

## continue if on the host

if [[ ! -f /etc/srvctl/debug.conf ]]
then
    echo "DEBUG=true" > /etc/srvctl/debug.conf
    msg "Debugging turned on - /etc/srvctl/debug.conf"
fi

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
run_hooks update-install-host

if $SC_USE_GUI
then
    make_commands_spec
fi

set_permissions
msg "update-install complete"
echo ""
