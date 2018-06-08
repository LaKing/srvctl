#!/bin/bash

if [[ "$(systemctl is-active mariadb.service)" == active ]]
then
    echo true
else
    source "$SC_INSTALL_DIR/modules/ve/module-condition.sh"
fi
