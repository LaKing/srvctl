#!/bin/bash

sudo mkdir -p /usr/local/share/srvctl
cd /usr/local/share/srvctl

sudo git clone https://github.com/LaKing/srvctl.git
sudo /usr/local/share/srvctl/srvctl.sh

if [[ $1 == dev ]]
then
    sudo rsync --delete -avze ssh root@r2.d250.hu:/srv/srvctl-devel/rootfs/srv/codepad-project/* /usr/local/share/srvctl
    sudo rsync --delete -avze ssh root@r2.d250.hu:/srv/srvctl-devel/rootfs/etc/srvctl/data /etc/srvctl
fi

