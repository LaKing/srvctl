#!/bin/bash

msg "Installing bind/named DNS server."


function procedure_write_dyndns_server_service {
    local crt
    crt="/etc/srvctl/cert/$CDN/$CDN"
cat > /lib/systemd/system/dyndns-server.service << EOF
## $SRVCTL generated
[Unit]
Description=Dyndns server.
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node "$SC_INSTALL_DIR"/modules/named/hs-apps/dyndns-server.js "$crt.key" "$crt.crt"
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
}

function procedure_write_etc_named_conf {
cat > /etc/named.conf << EOF
// $SRVCTL generated named.conf

acl "trusted" {
     10.0.0.0/8;
     localhost;
     localnets;
 };

options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    directory         "/var/named";
    dump-file         "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    allow-query     { any; };
    allow-recursion { trusted; };
    allow-query-cache { trusted; };
    recursion yes;
    dnssec-enable yes;
    dnssec-validation yes;
    dnssec-lookaside auto;
    bindkeys-file "/etc/named.iscdlv.key";
    managed-keys-directory "/var/named/dynamic";
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
    type hint;
    file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";

include "/var/named/srvctl-includes.conf";
EOF
}

function procedure_write_named_srvctl_include_key_conf {
cat > /var/named/srvctl-include-key.conf << EOF
## srvctl dyndns key
key "srvctl." {
  algorithm hmac-md5;
  secret "${_key:5}";
};
EOF
}


### procedures defined, now back to running code

[[ -f /usr/sbin/named ]] || sc_install bind bind-utils ntp

run systemctl enable ntpd
run systemctl start ntpd

## configure DNS server
## no recursion to prevent DNS amplifiaction attacks
if grep -q "$SRVCTL" /etc/named.conf
then
    
    msg "Configure BIND"
    ## DNS needs NTPD enabled and running, otherwise queries may get no response.
    
    procedure_write_etc_named_conf
    
    echo "## $SRVCTL generated" > "/var/$SRVCTL/named.conf.local"
    
    rsync -a /usr/share/doc/bind/sample/etc/named.rfc1912.zones /etc
    rsync -a /usr/share/doc/bind/sample/var/named /var
    mkdir -p /var/named/dynamic
    
    chown -R named:named /var/named #?/srvctl
    chmod 750 /var/named/srvctl
    add_service named
else
    msg "Bind - DNS server already configured."
fi

## dyndns stuff
## TODO dyndns should be really node user?

if [[ -f /etc/srvctl/cert/"$CDN/$CDN".key ]] && [[ -f /etc/srvctl/cert/"$CDN/$CDN".crt ]]
then
    
    if [[ ! -f /lib/systemd/system/dyndns-server.service ]]
    then
        log "Installing BIND based dyndns."
        
        mkdir -p /var/dyndns
        chown node:root /var/dyndns
        chmod 754 /var/dyndns
        
        procedure_write_dyndns_server_service
        
        systemctl daemon-reload
        systemctl enable dyndns-server
        systemctl start dyndns-server
    fi
    
    if [ ! -d /var/named/keys ]
    then
        local _this _key
        
        mkdir -p /var/named/keys
        _this="$(dnssec-keygen -K /var/named/keys -r /dev/urandom -a HMAC-MD5 -b 512 -n USER srvctl)"
        cat "/var/named/keys/$_this.key" > /var/named/keys/srvctl.key
        cat "/var/named/keys/$_this.private" > /var/named/keys/srvctl.private
        
        chown node /var/dyndns/srvctl.private
        chmod 400 /var/dyndns/srvctl.private
        
        _key="$(grep 'Key: ' "/var/named/keys/$_this.private")"
        
        procedure_write_named_srvctl_include_key_conf
        
        
        ## use it in dyndns-server
        cat /var/named/srvctl-include-key.conf > /var/dyndns/srvctl-include-key.conf
        chown node:node /var/dyndns/srvctl-include-key.conf
        chmod 400 /var/dyndns/srvctl-include-key.conf
        
        ## named needs to write to these folders for dyndns
        chown -R named:named /var/named #?/srvctl
        chmod 750 /var/named/srvctl
    fi
    
else
    msg "Skipping install for dyndns server due to a lack of certificates: /etc/srvctl/cert/$CDN/$CDN.key /etc/srvctl/cert/$CDN/$CDN.crt"
fi
