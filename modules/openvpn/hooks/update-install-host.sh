#!/bin/bash

## first install what's necessery
sc_install openvpn

if [[ -z $SC_ROOTCA_HOST ]]
then
    err "SC_ROOTCA_HOST not defined. The openvpn installation can not continue."
    return
fi

run mkdir -p /etc/openvpn

## then get the certificates
if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
then
    init_openvpn_rootca_certificates
else
    grab_openvpn_rootca_certificates
fi

run chmod 600 /etc/openvpn/*.key.pem

## generate this for the certificates
if [ ! -f /etc/openvpn/dh2048.pem ]
then
    run openssl dhparam -out /etc/openvpn/dh2048.pem 2048
fi

## make the virtual hostnet

if [[ $SC_HOSTNET ]]
then
    
    write_openvpn_server_config
    
    run chown -R openvpn:openvpn /etc/openvpn
    
    if [[ -f "/usr/lib/systemd/system/openvpn@.service" ]]
    then
        run systemctl enable openvpn@hostnet-server.service
        run systemctl restart openvpn@hostnet-server.service
        run systemctl status openvpn@hostnet-server.service --no-pager
    fi
    
    ## fedora 27 and up
    if [[ -f "/usr/lib/systemd/system/openvpn-server@.service" ]]
    then
        ln -s /etc/openvpn/hostnet-server.conf /etc/openvpn/server/hostnet-server.conf
        run systemctl enable openvpn-server@hostnet-server.service
        run systemctl restart openvpn-server@hostnet-server.service
        run systemctl status openvpn-server@hostnet-server.service --no-pager
    fi
    
    firewalld_add_service openvpn-hostnet udp 1101
    ##firewalld_add_service openvpn-usernet tcp 1100
    
else
    err "Openvpn configuration: SC_HOSTNET undefined"
fi

hostlist="$(cfg cluster host_list)"

for host in $hostlist
do
    if [[ "$host" == "$HOSTNAME" ]]
    then
        continue
    fi
    
    write_openvpn_client_config "$host"
    if [[ -f "/usr/lib/systemd/system/openvpn@.service" ]]
    then
        run systemctl enable "openvpn@hostnet-client-$host.service"
        run systemctl restart "openvpn@hostnet-client-$host.service"
        run systemctl status "openvpn@hostnet-client-$host.service" --no-pager
    fi
    
    ## fedora 27 and up
    if [[ -f "/usr/lib/systemd/system/openvpn-client@.service" ]]
    then
        ln -s /etc/openvpn/hostnet-client-"$host".conf /etc/openvpn/client/hostnet-client-"$host".conf
        run systemctl enable "openvpn-client@hostnet-client-$host.service"
        run systemctl restart "openvpn-cleint@hostnet-client-$host.service"
        run systemctl status "openvpn-client@hostnet-client-$host.service" --no-pager
        
        if [[ ! -f /etc/openvpn/server/hostnet-ccd ]]
        then
            ln -s /etc/openvpn/hostnet-ccd /etc/openvpn/server
        fi
    fi
    
done

return 0

