#!/bin/bash

## import certificates from root's folder to the system

[[ $SRVCTL ]] || exit 4

## certificate chainfile
local certpath
certpath="/etc/srvctl/cert/localhost"

if [[ -f /root/crt.pem ]] && [[ -f /root/crt.pem ]]
then
    
    msg "Import certificates from root"
    mkdir -p "$certpath"
    
    cat /root/crt.pem > "$certpath"/crt.pem
    cat /root/key.pem > "$certpath"/key.pem
    [[ -f /root/ca-bundle.pem ]] && cat /root/ca-bundle.pem > "$certpath"/ca-bundle.pem 2> /dev/null
    
    cat /root/crt.pem > "$certpath"/cert.pem
    # shellcheck disable=SC2129
    echo '' >> "$certpath"/cert.pem
    cat /root/key.pem >> "$certpath"/cert.pem
    echo '' >> "$certpath"/cert.pem
    [[ -f /root/ca-bundle.pem ]] && cat /root/ca-bundle.pem >> "$certpath"/cert.pem 2> /dev/null
else
    ntc "No certificates in /root directory to import."
fi


if [[ $SC_ROOTCA_HOST == $HOSTNAME ]]
then
    root_CA_init
fi
