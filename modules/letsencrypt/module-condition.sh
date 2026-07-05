#! /bin/bash

##
##   letsencrypt/module-condition.sh — module enable test.
##
##   Evaluated in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" to enable the module. Delegates to the containers module
##   condition, so letsencrypt is active exactly when containers is
##   (container-capable host listed in /etc/srvctl/hosts.json, or an
##   update-install run with an argument).
##
##   The module exposes no CLI commands: all work happens through the
##   update-install-host and regenerate_certificates hooks, libs/, and the
##   two node programs (letsencrypt.js, apps/acme-server.js).
##

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
