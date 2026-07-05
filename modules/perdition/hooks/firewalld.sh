#!/bin/bash

##
##   modules/perdition/hooks/firewalld.sh — open mail-proxy ports.
##
##   Sourced by 'run_hooks firewalld' from the firewalld module's
##   update-install hooks. Adds the imaps (993) and pop3s (995)
##   services to the host's default firewall zone, matching the two
##   externally-bound perdition listeners.
##

firewalld_add_service imaps
firewalld_add_service pop3s

## FIXME(v4): low — dead branch: the only path into this hook is the
## host-side update-install, where $container is unset (inside a VE
## the module is inactive). Even if it fired, opening imap (143) is
## pointless because imap4.service binds 127.0.0.1 only.
# shellcheck disable=SC2154
if [[ "${container:0:5}" == "mail." ]]
then
    firewalld_add_service imap
fi
