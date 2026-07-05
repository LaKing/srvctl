#! /bin/bash

##
##   modules/perdition/module-condition.sh — module activation test.
##
##   Sources the containers module condition verbatim: perdition is
##   enabled exactly when the containers module is (a real host listed
##   in hosts.json, never inside a container). Module status: half-
##   abandoned in v3 (its installer is disabled, see
##   hooks/update-install-host.sh); slated to be replaced by the G9
##   mail proxy in v4.
##

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
