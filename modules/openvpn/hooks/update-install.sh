#!/bin/bash

## first install what's necessery
sc_install openvpn

if [[ -z $SC_ROOTCA_HOST ]]
then
    err "SC_ROOTCA_HOST not defined. The openvpn installation can not continue."
    return
fi

mkdir -p /etc/openvpn

## then get the certificates
if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
then
    init_openvpn_rootca_certificates
else
    grab_openvpn_rootca_certificates
fi

chmod 600 /etc/openvpn/*.key.pem

## generate this for the certificates
if [ ! -f /etc/openvpn/dh2048.pem ]
then
    run openssl dhparam -out /etc/openvpn/dh2048.pem 2048
fi

## make the virtual hostnet

if [[ $SC_HOSTNET ]]
then
    
    write_openvpn_server_config
    
    chown -R openvpn:openvpn /etc/openvpn
    run systemctl enable openvpn@hostnet-server.service
    run systemctl restart openvpn@hostnet-server.service
    run systemctl status openvpn@hostnet-server.service --no-pager
    
    firewalld_add_service openvpn-hostnet udp 1101
    
else
    
    err "Openvpn configuration: SC_HOSTNET undefined"
fi

local hostlist
hostlist="$(cfg cluster host_list)"

for host in $hostlist
do
    if [[ "$host" == "$HOSTNAME" ]]
    then
        continue
    fi
    
    write_openvpn_client_config "$host"
    
    run systemctl enable "openvpn@hostnet-client-$host.service"
    run systemctl restart "openvpn@hostnet-client-$host.service"
    run systemctl status "openvpn@hostnet-client-$host.service" --no-pager
    
done


