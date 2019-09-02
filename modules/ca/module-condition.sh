#! /bin/bash

if [[ -d /etc/openvpn ]]
then
    echo true
    return
fi

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
return
#
# #! /bin/bash
# [[ -f /etc/srvctl/data/ca.conf ]] && source /etc/srvctl/data/ca.conf
# [[ -f /etc/srvctl/ca.conf ]] && source /etc/srvctl/ca.conf
#
# if [[ $SC_ROOTCA_HOST == "$HOSTNAME" ]]
# then
#     echo true
#     return
# fi
#
# echo false
