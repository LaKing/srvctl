#!/bin/bash

###
###        odoo module condition
###
###        Sourced at init; must output exactly "true" to enable the module.
###        The result is cached as SC_USE_ODOO in modules.conf.
###
###        Disabled in mail.* containers; otherwise delegates to the ve
###        module condition, which is true only inside systemd-nspawn/lxc
###        containers — so the module is never active on hosts.
###

container=$HOSTNAME

# shellcheck disable=SC2154
if [[ "${container:0:5}" == "mail." ]]
then
    echo false
else
    # shellcheck source=/usr/local/share/srvctl/modules/ve/module-condition.sh
    source "$SC_INSTALL_DIR/modules/ve/module-condition.sh"
fi
