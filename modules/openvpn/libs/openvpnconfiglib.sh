#!/bin/bash

##
##   modules/openvpn/libs/openvpnconfiglib.sh — generates the OpenVPN
##   hostnet config tree under /etc/openvpn.
##
##   Sourced by load_libs whenever SC_USE_OPENVPN=true; both writers are
##   called only from hooks/update-install-host.sh. Everything is inline
##   heredoc templating from SC_HOSTNET and datastore values, and the
##   running mesh depends on the output byte-for-byte: port 1101/udp, the
##   tun-hostnet / tun-host$hs device names, the 10.15.x.y addressing that
##   nfs/ssh/datastore consume, and cipher AES-256-CBC + comp-lzo that peers
##   of mixed versions must still handshake with. Do not alter generated
##   content before the zerotier migration (v4, G8) retires the mesh.
##

## Write /etc/openvpn/hostnet-server.conf (plus the hostnet-server.sh
## manual-start helper and the hostnet-ccd iroute file) for this host's
## mesh server on udp 1101, tun-hostnet, ifconfig 10.15.$SC_HOSTNET.1.
function write_openvpn_hostnet_server_config() {
    
    msg "Writing openvpn hostnet-server config"
    
    ## fedora 27
    mkdir -p /etc/openvpn/hostnet-ccd
    echo "iroute 10.15.$SC_HOSTNET.0 255.255.255.0" >  /etc/openvpn/hostnet-ccd/DEFAULT
    
    ## fedora 28
    mkdir -p /etc/openvpn/server/hostnet-ccd
    ## FIXME(v4): high — this line re-writes the fedora-27 path instead of
    ## /etc/openvpn/server/hostnet-ccd/DEFAULT; openvpn-server@ runs with
    ## WorkingDirectory=/etc/openvpn/server, so "client-config-dir
    ## hostnet-ccd" resolves to the empty directory created just above and
    ## the iroute is never applied on split-unit (Fedora 28+) hosts.
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
    
    ## FIXME(v4): the usernet TODO (tcp 1100) has been pending since v3 —
    ## usernet certificates are minted and distributed by
    ## hooks/update-install-host.sh, but no usernet server config is ever
    ## written; decide in v4 whether to implement it or stop minting.

}

## Write /etc/openvpn/hostnet-client-$1.conf: the client tunnel from this
## host to peer $1 (dev tun-host$hs, remote its host_ip on udp 1101), with
## the peer's address data read from the datastore. Bails out silently when
## host_ip or hostnet is missing, or when $1 is this host — the caller still
## enables a unit for it (see the FIXME in hooks/update-install-host.sh).
function write_openvpn_client_config() { ## host
    local host conf ip hs
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
