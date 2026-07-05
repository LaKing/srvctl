#!/bin/bash

###
###        mariadb module condition
###
###        Sourced at init in a subshell; must output exactly "true" to
###        enable the module. The result is cached as SC_USE_MARIADB in
###        modules.conf. Enabled when mariadb.service is active on this
###        machine; otherwise it falls through to the ve condition, which
###        prints true inside any systemd-nspawn or lxc container.
###

if [[ "$(systemctl is-active mariadb.service)" == active ]]
then
    echo true
else
    ## FIXME(v4): low — the ve fallthrough enables this module in every
    ## container, even ones with no mariadb installed at all.
    # shellcheck source=/usr/local/share/srvctl/modules/ve/module-condition.sh
    # shellcheck disable=SC1091 ## cross-module
    source "$SC_INSTALL_DIR/modules/ve/module-condition.sh"
fi
