#!/bin/bash

sudo mkdir -p /usr/local/share/srvctl
cd /usr/local/share/srvctl || exit

sudo dnf -y install git
sudo git clone https://github.com/LaKing/srvctl.git
sudo /usr/local/share/srvctl/srvctl.sh

if [[ $1 == dev ]]
then
    sudo rsync --delete -avze ssh root@bp.d250.hu:/srv/srvctl-devel/rootfs/srv/codepad-project/* /usr/local/share/srvctl
    sudo rsync --delete -avze ssh root@bp.d250.hu:/srv/srvctl-devel/rootfs/srv/codepad-project/example-conf/data /etc/srvctl
fi

#  bash /usr/local/share/srvctl/srvctl.sh
