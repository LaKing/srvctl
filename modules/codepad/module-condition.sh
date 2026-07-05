#!/bin/bash

##
##   codepad/module-condition.sh — decide whether the codepad module is
##   enabled on this system.
##
##   Sourced in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" to enable the module, the result is cached as
##   SC_USE_CODEPAD in modules.conf. Prints "false" inside containers
##   and on mail.* hosts, otherwise delegates to the containers module
##   condition (enabled exactly when containers are enabled).
##

SC_VIRT=$(systemd-detect-virt -c)
container=$HOSTNAME

## lxc is deprecated, but we can consider it a container ofc.
if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]] || [[ "${container:0:5}" == "mail." ]]
then
    echo false
    return
fi
## resolved at runtime relative to the install dir
# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
# shellcheck disable=SC1091 # runtime-path
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
