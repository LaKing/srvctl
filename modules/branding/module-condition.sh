#!/bin/bash

##
##   modules/branding/module-condition.sh — module activation test.
##
##   Sourced in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" to enable the module. Branding delegates entirely to
##   the containers module condition, so branding is enabled exactly
##   when containers is. The result is cached as SC_USE_BRANDING in
##   modules.conf.
##

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
# shellcheck disable=SC1091 ## runtime-path
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
