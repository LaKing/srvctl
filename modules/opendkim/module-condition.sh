#! /bin/bash

## modules/opendkim/module-condition.sh
## Module condition for the opendkim module, evaluated at init in a
## subshell by test_srvctl_modules (commonlib.sh); the value echoed on
## stdout is cached in modules.conf as SC_USE_OPENDKIM. Delegates by
## sourcing the containers module's condition verbatim, so opendkim is
## enabled exactly when containers is — i.e. on container-farm hosts,
## including the update-install bootstrap path.

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
# shellcheck disable=SC1091 # runtime-path
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
