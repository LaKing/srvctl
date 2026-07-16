#! /bin/bash

##
##   certificates/module-condition.sh — module enable test.
##
##   Evaluated in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" to enable the module. Delegates to the containers module
##   condition, so certificates is active exactly when containers is
##   (container-capable host listed in /var/srvctl3/host/hosts.json, or an
##   update-install run with an argument).
##
##   The module exposes no CLI commands; it provides certificate library
##   functions and hooks consumed by haproxy, containers, gui, postfix,
##   perdition and named, plus openssl-server-ext.cnf used by the ca module.
##

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
