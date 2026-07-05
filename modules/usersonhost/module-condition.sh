#! /bin/bash

##
##   modules/usersonhost/module-condition.sh — activation test.
##
##   Sourced at init time (and by regenerate-modules) to decide whether
##   usersonhost is enabled. It has no test of its own: it sources the
##   containers module condition and inherits its verdict, so usersonhost
##   is active exactly where containers is — on real cluster hosts (not
##   inside nspawn/lxc containers, hostname not localhost.localdomain,
##   listed in /etc/srvctl/hosts.json), or during "update-install <arg>".
##   Net effect: host-side user management never runs inside a container.
##

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
