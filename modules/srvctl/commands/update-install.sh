#!/bin/bash

root_only #|| return 244

## @en Run the installation/update script.
## &en Update/Install all components
## &en On host systems install the containerfarm

sc_update

## install mc if we dont have it
[[ -f /bin/mc ]] || sc_install mc
[[ -f /bin/node ]] || sc_install nodejs

## source custom configurations
if [[ ! -f /etc/srvctl/config ]]
then
    mkdir -p /etc/srvctl
    cat "$SC_INSTALL_DIR/config" > /etc/srvctl/config
fi

msg "Calling update-install hooks."
run_hooks update-install
