#! /bin/bash

SC_VIRT=$(systemd-detect-virt -c)
container=$HOSTNAME

## lxc is deprecated, but we can consider it a container ofc.
if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]] || [[ "${container:0:5}" == "mail." ]]
then
    echo false
    return
fi
# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
