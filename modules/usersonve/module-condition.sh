#! /bin/bash

## Module condition, sourced (in a subshell) at init: usersonve is enabled
## exactly when the ve module is — only INSIDE containers (systemd-nspawn or
## lxc), never on the host. Re-sources the ve condition verbatim, which
## prints "true" or "false" as its only stdout.
# shellcheck source=/usr/local/share/srvctl/modules/ve/module-condition.sh
source "$SC_INSTALL_DIR/modules/ve/module-condition.sh"
