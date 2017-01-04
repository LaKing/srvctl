#!/bin/bash

msg "host config file (data)"

## skip if we dont have node
[[ -f /bin/node ]] || return

## load datalib if we have
source "$SC_INSTALL_DIR/modules/datastore/libs/datalib.sh"

msg "Writing host config file (data)"

out host "$HOSTNAME" > /etc/srvctl/host.conf
