#!/bin/bash

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
    local key
    key="$1"
cat > /var/named/srvctl-include-key.conf << EOF
## srvctl dyndns key
key "srvctl." {
  algorithm hmac-md5;
  secret "${key:5}";
};
EOF
}
