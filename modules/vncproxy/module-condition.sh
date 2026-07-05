#! /bin/bash

## vncproxy module condition — sourced (in a subshell) at init to decide
## whether the module is enabled. Delegates entirely to the containers
## module: vncproxy is active exactly when the containers module is.

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
