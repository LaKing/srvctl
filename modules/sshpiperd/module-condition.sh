#!/bin/bash

##
##   modules/sshpiperd/module-condition.sh — module activation test.
##
##   Sourced in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" or "false". Delegates entirely to the containers
##   module's condition, so sshpiperd is active exactly where containers
##   is: on farm hosts (not localhost.localdomain, not itself a
##   container, SC_HOSTNET set or /etc/srvctl/data present, $HOSTNAME in
##   /etc/srvctl/hosts.json) and on the 'update-install <host>'
##   bootstrap path. The result is cached as SC_USE_SSHPIPERD in
##   modules.conf.
##

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
