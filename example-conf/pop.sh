#!/bin/bash

sudo mkdir -p /usr/share/srvctl
cd /usr/share/srvctl

sudo git clone https://github.com/LaKing/srvctl.git

if [[ ! -e /bin/sc ]]
then
    sudo ln -s /usr/share/srvctl/srvctl.sh /bin/sc
fi
