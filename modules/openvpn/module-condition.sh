#! /bin/bash

if [[ -d /etc/openvpn ]]
then
	echo true
    return
fi


# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"