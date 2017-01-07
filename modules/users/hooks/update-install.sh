#!/bin/bash

## srvctl3 sudo functions
sc_install sudo
echo '## srvctl v3 sudo file' > /etc/sudoers.d/srvctl
echo 'ALL ALL=(ALL) NOPASSWD: /usr/share/srvctl/srvctl.sh *' >> /etc/sudoers.d/srvctl
