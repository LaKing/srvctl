#!/bin/bash

##
##   modules/named/installnamedlib.sh — heredoc write procedures for the
##   installer. NOT auto-loaded as a module lib: sourced on demand by
##   install_named (libs/install.sh). Generated file contents are
##   production DNS configuration — keep them byte-identical.
##
##   procedure_write_etc_named_conf                  live: /etc/named.conf
##   procedure_write_dyndns_server_service           dormant (dead dyndns)
##   procedure_write_named_srvctl_include_key_conf   dormant (dead dyndns)
##

## DORMANT — only reachable from the disabled install_dyndns.
## FIXME(v4): medium (dormant) — ExecStart points at
## modules/named/hs-apps/dyndns-server.js but the file lives at
## modules/named/apps/dyndns-server.js; the unit could never start.
function procedure_write_dyndns_server_service {
    local crt
    crt="/etc/srvctl/cert/$SC_COMPANY_DOMAIN/$SC_COMPANY_DOMAIN"
    
    ## TODO remove after update
    rm -fr /usr/lib/systemd/system/dyndns-server.service
    
cat > /etc/systemd/system/dyndns-server.service << EOF
## $SRVCTL generated
[Unit]
Description=Dyndns server.
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node "$SC_INSTALL_DIR"/modules/named/hs-apps/dyndns-server.js "$crt.key" "$crt.crt"
User=root
Group=root
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

## Overwrites /etc/named.conf on every update-install. Recursion is
## allowed only for the trusted ACL (10.0.0.0/8 + local) to prevent DNS
## amplification; the srvctl-managed zones arrive via the
## /var/named/srvctl.conf include, written by named.js at regenerate.
## FIXME(v4): high (latent) — the hard-coded include of /var/named/d250.conf
## (a company-specific file nothing in this repo creates) makes named fail
## to load its whole configuration on any fresh install where it is absent;
## existing production masters rely on it, so this needs a migration
## decision (e.g. emit the include only if the file exists), not a silent
## removal.
## FIXME(v4): medium — bindkeys-file "/etc/named.iscdlv.key" is an obsolete
## BIND option (removed in bind 9.16+); recent named logs errors on it.
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
    dnssec-validation yes;
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

include "/var/named/d250.conf";
include "/var/named/srvctl.conf";
EOF
}

## DORMANT — only reachable from the disabled install_dyndns. Writes the
## TSIG key include for nsupdate; $1 is the 'Key: <secret>' line from the
## generated .private file (hence the :5 offset below). hmac-md5 is
## obsolete — a v4 revival should switch to tsig-keygen output.
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
