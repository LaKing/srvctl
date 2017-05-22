#!/bin/bash

## Postfix mail, incoming and outgoing on hosts and containers

msg "Installing perdition. Custom service files are: imap4.service, imap4s.service, pop3s.service"

sc_install perdition

## deal with certificates
## TODO add wildcard certificate for CDN

cat "/etc/srvctl/cert/$HOSTNAME/$HOSTNAME.pem" > /etc/perdition/crt.pem
cat "/etc/srvctl/cert/$HOSTNAME/$HOSTNAME.key" > /etc/perdition/key.pem

chmod 400 /etc/perdition/crt.pem
chmod 400 /etc/perdition/key.pem


cat "$SC_INSTALL_DIR/modules/perdition/conf/perdition.conf" > /etc/perdition/perdition.conf

if [ -f /etc/srvctl/cert/ca-bundle.pem ]
then
    cat /etc/srvctl/cert/ca-bundle.pem > /etc/perdition/ca-bundle.pem
    echo "ssl_ca_chain_file = /etc/perdition/ca-bundle.pem" >> /etc/perdition/perdition.conf
fi


echo "#### srvctl tuned popmap.re" > /etc/perdition/popmap.re
## popmap.re needs to be generated


mkdir -p /var/run/perdition
mkdir -p /var/perdition

perditioncfg

## install services

cat "$SC_INSTALL_DIR/modules/perdition/services/imap4s.service" > /usr/lib/systemd/system/imap4s.service
cat "$SC_INSTALL_DIR/modules/perdition/services/imap4.service" > /usr/lib/systemd/system/imap4.service
cat "$SC_INSTALL_DIR/modules/perdition/services/pop3s.service" > /usr/lib/systemd/system/pop3s.service

add_service imap4
add_service imap4s
add_service pop3s

systemctl daemon-reload
