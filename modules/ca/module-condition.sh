#!/bin/bash

##
##   modules/ca/module-condition.sh — decides whether the ca module is
##   enabled. Sourced by test_srvctl_modules (commonlib.sh) inside a
##   command-substitution subshell; must print "true" or "false".
##
##   Enabled when /etc/openvpn exists (any host with the openvpn package
##   installed); otherwise falls through to the containers module
##   condition (true on real cluster hosts).
##

## FIXME(v4): the /etc/openvpn check runs before any container guard, so the
## module (and its hooks) also activates inside nspawn guests that happen to
## have the openvpn package installed.
if [[ -d /etc/openvpn ]]
then
    echo true
    return
fi

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
return
