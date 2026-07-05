#!/bin/bash

##
##   modules/openvpn/module-condition.sh — decides whether the openvpn
##   module is enabled. Sourced by test_srvctl_modules (commonlib.sh) inside
##   a command-substitution subshell; must print "true" or "false". The
##   result is cached as SC_USE_OPENVPN in modules.conf.
##
##   Enabled when /etc/openvpn exists (any already-provisioned host, even if
##   cluster membership data is absent); otherwise falls through to the
##   containers module condition (true on real cluster hosts). The ca module
##   keys off the same -d /etc/openvpn test, so wherever openvpn activates
##   via that path, ca activates too.
##
##   The whole module is a deprecation candidate for v4 (campaign issue G8:
##   the zerotier mesh replaces the 10.15.x.y OpenVPN hostnet), but it is
##   LIVE on production hosts until that migration completes.
##

## FIXME(v4): the /etc/openvpn check runs before any container guard, so the
## module (and its hooks) also activates inside nspawn guests that happen to
## have the openvpn package installed (same pattern as modules/ca).
if [[ -d /etc/openvpn ]]
then
    echo true
    return
fi


# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
