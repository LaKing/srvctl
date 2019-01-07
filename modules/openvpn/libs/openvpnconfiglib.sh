#!/bin/bash

function write_openvpn_server_config() {
    
    msg "Writing openvpn hostnet-server config"
    
    ## fedora 27
    mkdir -p /etc/openvpn/hostnet-ccd
    echo "iroute 10.15.$SC_HOSTNET.0 255.255.255.0" >  /etc/openvpn/hostnet-ccd/DEFAULT
    
    ## fedora 28
    mkdir -p /etc/openvpn/server/hostnet-ccd
    echo "iroute 10.15.$SC_HOSTNET.0 255.255.255.0" >  /etc/openvpn/hostnet-ccd/DEFAULT
    
cat > "/etc/openvpn/hostnet-server.conf" << EOF
## srvctl-created openvpn-server conf
topology subnet
mode server
port 1101
dev tun-hostnet
proto udp
status hostnet.log 60
status-version 2
user openvpn
group openvpn
persist-tun
persist-key
keepalive 10 60
inactive 600
verb 4
comp-lzo
script-security 2
cipher AES-256-CBC
tls-server
ca /etc/openvpn/hostnet-ca.crt.pem
cert /etc/openvpn/hostnet-server.crt.pem
key /etc/openvpn/hostnet-server.key.pem
dh /etc/openvpn/dh2048.pem
client-config-dir hostnet-ccd

EOF
    
    echo "ifconfig 10.15.$SC_HOSTNET.1 255.255.255.0" >> /etc/openvpn/hostnet-server.conf
    
    ## additional helper to start the service
    
cat > "/etc/openvpn/hostnet-server.sh" << EOF
echo "start hostnet-server"
/usr/sbin/openvpn --cd /etc/openvpn/ --config hostnet-server.conf
EOF
    
    chmod +x /etc/openvpn/hostnet-server.sh
    
    ## TODO openvpn-usernet tcp 1100
    ##
    ##
    
}

function write_openvpn_client_config() { ## host
    local host conf
    host="$1"
    conf="/etc/openvpn/hostnet-client-$host.conf"
    
    ip="$(get host "$host" host_ip)"
    hs="$(get host "$host" hostnet)"
    
    ## for each other publicly available server
    if [[ -z $ip ]] || [[ -z $hs ]]
    then
        return
    fi
    if [[ $host == "$HOSTNAME" ]]
    then
        return
    fi
    
    msg "Writing openvpn hostnet-client config for $host ($ip) $hs"
    
cat > "$conf" << EOF
## srvctl hostnet openvpn client file for $host (HOSTNET $hs)
topology subnet
client
dev tun-host$hs
proto udp
remote $ip 1101
nobind
persist-key
persist-tun
remote-cert-tls server
ca /etc/openvpn/hostnet-ca.crt.pem
cert /etc/openvpn/hostnet-client.crt.pem
key /etc/openvpn/hostnet-client.key.pem
comp-lzo
verb 3
cipher AES-256-CBC

EOF
    
    echo "ifconfig 10.15.$hs.$SC_HOSTNET 255.255.255.0" >> "$conf"
    echo "route 10.$hs.0.0 255.255.0.0 10.15.$hs.1" >> "$conf"
    
}
