#!/bin/bash

##
##   modules/datastore/module-condition.sh — decides whether the datastore
##   module is enabled. Sourced by test_srvctl_modules (commonlib.sh) inside
##   a command-substitution subshell; must print "true" or "false".
##
##   Delegates entirely to the containers module condition: the datastore is
##   active exactly where containers are managed (real cluster hosts listed
##   in /etc/srvctl/hosts.json, not inside nspawn/lxc guests).
##

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
