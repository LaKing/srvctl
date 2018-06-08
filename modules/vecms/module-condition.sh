#! /bin/bash

if [[ "${container:0:5}" == "mail." ]]
then
    return false
else
    source "$SC_INSTALL_DIR/modules/ve/module-condition.sh"
fi
