#!/bin/bash

## Due to incompatibility of saslauthd <= 2.1.26 and perdition, a custom version of saslauthd is required

msg "Installing saslauthd - binary for x86_64"

{
    echo "pwcheck_method: saslauthd"
    echo "mech_list: LOGIN"
    
} > /etc/sasl2/smtpd.conf

cp "$SC_INSTALL_DIR/modules/saslauthd/bin/saslauthd" /usr/sbin/saslauthd
chmod 755 /usr/sbin/saslauthd
saslauthd -v

cat "$SC_INSTALL_DIR/modules/saslauthd/conf/saslauthd.conf" > /etc/sysconfig/saslauthd

cat "$SC_INSTALL_DIR/modules/saslauthd/services/saslauthd.service" > /usr/lib/systemd/system/saslauthd.service

add_service saslauthd

systemctl daemon-reload
