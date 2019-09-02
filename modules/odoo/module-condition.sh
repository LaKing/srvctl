#! /bin/bash

container=$HOSTNAME

# shellcheck disable=SC2154
if [[ "${container:0:5}" == "mail." ]]
then
    echo false
else
    # shellcheck source=/usr/local/share/srvctl/modules/ve/module-condition.sh
    source "$SC_INSTALL_DIR/modules/ve/module-condition.sh"
fi
