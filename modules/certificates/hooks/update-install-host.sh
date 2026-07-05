#!/bin/bash

##
##   certificates/hooks/update-install-host.sh
##
##   Sourced via 'run_hooks update-install-host' from 'srvctl update-install'
##   (modules/srvctl/commands/update-install.sh). Ensures /etc/srvctl/cert
##   exists, initializes the root CA on the designated SC_ROOTCA_HOST
##   (root_CA_init, ca module) and installs the acme client/server
##   (install_acme, letsencrypt module).
##

## import certificates from root's folder to the system

[[ $SRVCTL ]] || exit 4

mkdir -p /etc/srvctl/cert

## The /root/crt.pem import block below is a disabled feature stub.
## Kept commented out on purpose: the v4 campaign decides whether
## root-import becomes a real feature or gets deleted.

## certificate chainfile
#local certpath
#certpath="/etc/srvctl/cert/localhost"

#if [[ -f /root/crt.pem ]] && [[ -f /root/crt.pem ]]
#then
#
#    msg "Import certificates from root"
#    mkdir -p "$certpath"
#
#    cat /root/crt.pem > "$certpath"/crt.pem
#    cat /root/key.pem > "$certpath"/key.pem
#    [[ -f /root/ca-bundle.pem ]] && cat /root/ca-bundle.pem > "$certpath"/ca-bundle.pem 2> /dev/null
#
#    cat /root/crt.pem > "$certpath"/cert.pem
#    # shellcheck disable=SC2129
#    echo '' >> "$certpath"/cert.pem
#    cat /root/key.pem >> "$certpath"/cert.pem
#    echo '' >> "$certpath"/cert.pem
#    [[ -f /root/ca-bundle.pem ]] && cat /root/ca-bundle.pem >> "$certpath"/cert.pem 2> /dev/null
#else
#    ntc "No certificates in /root directory to import."
#fi

if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
then
    ## FIXME(v4): root_CA_init is called with no argument, creating a nameless
    ## CA (/etc/srvctl/CA/ca/.key.pem etc.) that no create_ca_certificate
    ## caller ever references — wasted keygen and a stray unmanaged key.
    root_CA_init
fi

## FIXME(v4): install_acme also runs from the letsencrypt module's own
## update-install-host hook (alphabetical module order runs both), so every
## update-install performs the acme install twice.
install_acme
