#!/bin/bash

sudo mkdir -p /usr/local/share/srvctl
cd /usr/local/share/srvctl

sudo git clone https://github.com/LaKing/srvctl.git

if [[ ! -e /bin/sc ]]
then
    sudo ln -s /usr/local/share/srvctl/srvctl.sh /bin/sc
fi
