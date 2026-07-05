#! /bin/bash

## Module condition, sourced (in a subshell) at init: saslauthd is enabled
## exactly when the containers module is — this file simply re-sources the
## containers condition, since SMTP AUTH only makes sense on container hosts.
# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
