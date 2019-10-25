#!/bin/bash


run dnf -y install cyrus-sasl

msg "Installing saslauthd - binary for x86_64"

{
    echo "pwcheck_method: saslauthd"
    echo "mech_list: LOGIN"
    
} > /etc/sasl2/smtpd.conf

## Due to incompatibility of saslauthd <= 2.1.26 and perdition, a custom version of saslauthd is required - this seems to be OK now.
#msg "Copy the patched saslauthd"
#cp "$SC_INSTALL_DIR/modules/saslauthd/bin/saslauthd" /usr/sbin/saslauthd
#chmod 755 /usr/sbin/saslauthd

run saslauthd -v

#TODO check this, if it was successful?

cat "$SC_INSTALL_DIR/modules/saslauthd/conf/saslauthd.conf" > /etc/sysconfig/saslauthd

cat "$SC_INSTALL_DIR/modules/saslauthd/services/saslauthd.service" > /usr/lib/systemd/system/saslauthd.service

add_service saslauthd

run systemctl daemon-reload
