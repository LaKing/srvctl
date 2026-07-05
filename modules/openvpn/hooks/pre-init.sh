#!/bin/bash

##
##   modules/openvpn/hooks/pre-init.sh — openvpn configuration default.
##
##   Runs on every srvctl invocation, after /etc/srvctl/*.conf has been
##   sourced, so site config wins and this line only fills in an unset
##   value. Deprecation candidate for v4 (G8: zerotier replaces the mesh).
##

## FIXME(v4): smell — SC_OPENVPN_HOSTNET_SERVER is defaulted on every
## invocation but read by nothing in the repo (dead knob); grep production
## /etc/srvctl/*.conf before removing it.
# shellcheck disable=SC2034
[[ $SC_OPENVPN_HOSTNET_SERVER ]] || SC_OPENVPN_HOSTNET_SERVER=$HOSTNAME
