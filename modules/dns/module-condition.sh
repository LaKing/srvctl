#! /bin/bash

## modules/dns/module-condition.sh
## Module condition for the dns module, evaluated at init in a subshell;
## the value echoed on stdout is cached in modules.conf as SC_USE_DNS.
## Delegates by sourcing the containers module's condition verbatim, so
## dns is enabled exactly when containers is. This works only because
## conditions run in subshells (commonlib.sh): the sourced file's
## readonly SC_VIRT cannot clash with the parent shell.

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
# shellcheck disable=SC1091 # runtime-path
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
