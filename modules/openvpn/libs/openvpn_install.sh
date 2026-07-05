#!/bin/bash

##
##   modules/openvpn/libs/openvpn_install.sh — DEAD CODE, no callers.
##
##   install_openvpn is invoked by nothing anywhere in the repo (only
##   reachable by hand via "srvctl exec-function install_openvpn"), and its
##   name is misleading next to "sc_install openvpn" — the package install
##   in hooks/update-install-host.sh. It would initialize a per-host
##   "$HOSTNAME-net" CA and mint a root client certificate: a leftover of a
##   pre-hostnet design.
##
## FIXME(v4): drop this file — dead code; the whole module is a deprecation
## candidate (G8: zerotier replaces the mesh).

function install_openvpn() { #net #ip #serverport

    msg install_openvpn

    NET="$HOSTNAME-net"

    root_CA_init "$NET"

    create_ca_certificate client "$NET" root

}
