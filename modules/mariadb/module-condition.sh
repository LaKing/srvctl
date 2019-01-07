#!/bin/bash

if [[ "$(systemctl is-active mariadb.service)" == active ]]
then
    echo true
else
    # shellcheck source=/usr/local/share/srvctl/modules/ve/module-condition.sh
    source "$SC_INSTALL_DIR/modules/ve/module-condition.sh"
fi
