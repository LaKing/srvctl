#! /bin/bash

## modules/mozilla/module-condition.sh
## Module condition for the mozilla module, evaluated at init in a subshell;
## the value echoed on stdout is cached in modules.conf as SC_USE_MOZILLA.
## Delegates by sourcing the haproxy module's condition verbatim (which in
## turn delegates to the containers condition), so mozilla is enabled
## exactly when containers is — i.e. on container-farm hosts. Note this is
## a path coupling, not a declared dependency: if the haproxy condition
## file moved, mozilla would silently evaluate to disabled.

# shellcheck source=/usr/local/share/srvctl/modules/haproxy/module-condition.sh
# shellcheck disable=SC1091 # runtime-path
source "$SC_INSTALL_DIR/modules/haproxy/module-condition.sh"
