#!/bin/bash

## first install what's necessery
sc_install openvpn

if [[ -z $SC_ROOTCA_HOST ]]
then
    err "SC_ROOTCA_HOST not defined. The openvpn installation can not continue."
    return
fi


## then get the certificates
if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
then
    
    root_CA_init hostnet
    root_CA_init usernet
    
    create_ca_certificate client usernet root
    create_ca_certificate client hostnet root
    
    create_ca_certificate server usernet "$HOSTNAME"
    create_ca_certificate server hostnet "$HOSTNAME"
    
    create_ca_certificate client usernet "$HOSTNAME"
    create_ca_certificate client hostnet "$HOSTNAME"
    
    cat /etc/srvctl/CA/ca/usernet.crt.pem > /etc/openvpn/usernet-ca.crt.pem
    cat /etc/srvctl/CA/ca/hostnet.crt.pem > /etc/openvpn/hostnet-ca.crt.pem
    
    cat /etc/srvctl/CA/usernet/server-"$HOSTNAME".key.pem > /etc/openvpn/usernet-server.key.pem
    cat /etc/srvctl/CA/usernet/server-"$HOSTNAME".crt.pem > /etc/openvpn/usernet-server.crt.pem
    
    cat /etc/srvctl/CA/hostnet/server-"$HOSTNAME".key.pem > /etc/openvpn/hostnet-server.key.pem
    cat /etc/srvctl/CA/hostnet/server-"$HOSTNAME".crt.pem > /etc/openvpn/hostnet-server.crt.pem
    
    cat /etc/srvctl/CA/usernet/client-"$HOSTNAME".key.pem > /etc/openvpn/usernet-client.key.pem
    cat /etc/srvctl/CA/usernet/client-"$HOSTNAME".crt.pem > /etc/openvpn/usernet-client.crt.pem
    
    cat /etc/srvctl/CA/hostnet/client-"$HOSTNAME".key.pem > /etc/openvpn/hostnet-client.key.pem
    cat /etc/srvctl/CA/hostnet/client-"$HOSTNAME".crt.pem > /etc/openvpn/hostnet-client.crt.pem
    
    for S in $(cfg system host_list)
    do
        ## openvpn client certificate
        create_ca_certificate server usernet "$S"
        create_ca_certificate server hostnet "$S"
        
        create_ca_certificate client usernet "$S"
        create_ca_certificate client hostnet "$S"
    done
    
else
    
    if [ "$(ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" hostname 2> /dev/null)" == "$SC_ROOTCA_HOST" ]
    then
        
        msg "regenerate openvpn certificate config - CA is $SC_ROOTCA_HOST"
        local H options
        H="$HOSTNAME"
        
        options="--no-R --no-implied-dirs -avze ssh"
        
        if [ ! -f /etc/openvpn/usernet-ca.crt.pem ] || [ ! -f /etc/openvpn/hostnet-ca.crt.pem ]
        then
            msg "Grabbing CA certificates from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options" "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/ca/usernet.crt.pem" /etc/openvpn/usernet-ca.crt.pem
            run rsync "$options" "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/ca/hostnet.crt.pem" /etc/openvpn/hostnet-ca.crt.pem
        fi
        
        if [ ! -f /etc/openvpn/usernet-server.crt.pem ] || [ ! -f /etc/openvpn/usernet-server.key.pem ]
        then
            msg "Grabbing usernet $HOSTNAME server certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/usernet/server-$H.crt.pem" /etc/openvpn/usernet-server.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/usernet/server-$H.key.pem" /etc/openvpn/usernet-server.key.pem
        fi
        
        if [ ! -f /etc/openvpn/hostnet-server.crt.pem ] || [ ! -f /etc/openvpn/hostnet-server.key.pem ]
        then
            msg "Grabbing hostnet $HOSTNAME server certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/hostnet/server-$H.crt.pem" /etc/openvpn/hostnet-server.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/hostnet/server-$H.key.pem" /etc/openvpn/hostnet-server.key.pem
        fi
        
        if [ ! -f /etc/openvpn/usernet-client.crt.pem ] || [ ! -f /etc/openvpn/usernet-client.key.pem ]
        then
            msg "Grabbing usernet $HOSTNAME client certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/usernet/client-$H.crt.pem" /etc/openvpn/usernet-client.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/usernet/client-$H.key.pem" /etc/openvpn/usernet-client.key.pem
        fi
        
        if [ ! -f /etc/openvpn/hostnet-client.crt.pem ] || [ ! -f /etc/openvpn/hostnet-client.key.pem ]
        then
            msg "Grabbing hostnet $HOSTNAME client certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/hostnet/client-$H.crt.pem" /etc/openvpn/hostnet-client.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/hostnet/client-$H.key.pem" /etc/openvpn/hostnet-client.key.pem
        fi
    else
        err "CA $SC_ROOTCA_HOST connection failed!"
    fi
    
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
    
    msg "Writing openvpn hostnet-server config"
    
cat > "/etc/openvpn/hostnet-server.conf" << EOF
## srvctl-created openvpn-server conf

mode server
port 1101
dev tap-hostnet
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

EOF
    
    echo "ifconfig 10.15.$SC_HOSTNET.$SC_HOSTNET 255.255.255.0" >> /etc/openvpn/hostnet-server.conf
    
    chown -R openvpn:openvpn /etc/openvpn
    run systemctl enable openvpn@hostnet-server.service
    run systemctl restart openvpn@hostnet-server.service
    run systemctl status openvpn@hostnet-server.service --no-pager
    
    firewalld_add_service openvpn-hostnet udp 1101
    
cat > "/etc/openvpn/hostnet-server.sh" << EOF
echo "start hostnet-server"
/usr/sbin/openvpn --cd /etc/openvpn/ --config hostnet-server.conf
EOF
    chmod +x /etc/openvpn/hostnet-server.sh
else
    
    err "Openvpn configuration: SC_HOSTNET undefined"
fi

local hostlist ip hs b
hostlist="$(cfg system host_list)"

for host in $hostlist
do
    
    ip="$(get host "$host" host_ip)"
    hs="$(get host "$host" hostnet)"
    
    if [[ ! -z $ip ]] && [[ ! -z $hs ]] && [[ $host != "$HOSTNAME" ]]
    then
        
        msg "Writing openvpn hostnet-client config for $host ($ip) $hs"
        
        cat > "/etc/openvpn/hostnet-client-$hs.conf" << EOF
## srvctl hostnet openvpn client file for $host
client
dev tap-host$hs
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
        
        echo "ifconfig 10.15.$hs.$SC_HOSTNET 255.255.255.0" >> "/etc/openvpn/hostnet-client-$hs.conf"
        
        b=$(( hs * 16 ))
        echo "route 10.$b.0.0 255.240.0.0 10.15.$hs.$hs" >> "/etc/openvpn/hostnet-client-$hs.conf"
        
        chown -R openvpn:openvpn /etc/openvpn
        run systemctl enable "openvpn@hostnet-client-$hs.service"
        run systemctl restart "openvpn@hostnet-client-$hs.service"
        run systemctl status "openvpn@hostnet-client-$hs.service" --no-pager
        
    fi
    
    
done

chown -R openvpn:openvpn /etc/openvpn

return

## will contain user files
mkdir -p /var/openvpn

## regenerate_users_configs

cat > /etc/openvpn/bridgeup.sh << 'EOF'
#!/bin/sh

BR=$1
DEV=$2
MTU=$3
/sbin/ip link set "$DEV" up promisc on mtu "$MTU"
/sbin/brctl addif "$BR" "$DEV"
exit 0

EOF

cat > /etc/openvpn/bridgedown.sh << 'EOF'
#!/bin/sh

BR=$1
DEV=$2
/sbin/brctl delif "$BR" "$DEV"
/sbin/ip link set "$DEV" down
exit 0

EOF


cat > /etc/openvpn/usernet-server.conf << EOF
## srvctl-created openvpn conf

mode server
port 1100
dev tap-usernet
proto udp
status usernet.log 60
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

up "/bin/bash bridgeup.sh srv-net tap-usernet 1500"
down "/bin/bash bridgedown.sh srv-net tap-usernet"

tls-server
ca /etc/openvpn/usernet-ca.crt.pem
cert /etc/openvpn/usernet-server.crt.pem
key /etc/openvpn/usernet-server.key.pem
dh /etc/openvpn/dh2048.pem

client-config-dir /var/openvpn
ccd-exclusive

server-bridge 10.0.0.1 255.0.0.0 10.0.250.1 10.0.253.250
EOF


return

## single host openvpn network would be ....


if [[ $HOSTNAME == "$SC_OPENVPN_HOSTNET_SERVER" ]]
then
    
cat > /etc/openvpn/hostnet.conf << EOF
## srvctl-created openvpn-server conf

mode server
port 1101
dev tap-hostnet
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

EOF
    
else
    
    ## for clients of the hostnet
    
cat > /etc/openvpn/hostnet.conf << EOF
## srvctl hostnet openvpn client file
client
dev tap-hostnet
proto udp
remote $SC_OPENVPN_HOSTNET_SERVER 1101
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
    
fi

local b

echo "ifconfig 10.15.0.$SC_HOSTNET 255.255.255.0" >> /etc/openvpn/hostnet.conf
for i in {1..16}
do
    if [[ $SC_HOSTNET == "$i" ]]
    then
        continue
    fi
    b=$(( i * 16 ))
    echo "route 10.$b.0.0 255.240.0.0 10.15.0.$i" >> /etc/openvpn/hostnet.conf
done

