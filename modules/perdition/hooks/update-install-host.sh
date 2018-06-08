#!/bin/bash

## Postfix mail, incoming and outgoing on hosts and containers

msg "Installing perdition. Custom service files are: imap4.service, imap4s.service, pop3s.service"

sc_install perdition

## TODO add wildcard certificate for CDN

install_service_hostcertificate /etc/perdition

cat "$SC_INSTALL_DIR/modules/perdition/conf/perdition.conf" > /etc/perdition/perdition.conf

## in seems to be unnecessery
# if [ -f /etc/perdition/ca-bundle.pem ]
# then
#     echo "ssl_ca_chain_file = /etc/perdition/ca-bundle.pem" >> /etc/perdition/perdition.conf
# fi


echo "#### srvctl tuned popmap.re" > /etc/perdition/popmap.re
## popmap.re needs to be generated


mkdir -p /var/run/perdition
mkdir -p /var/perdition

perditioncfg

## install services

rm -fr /usr/lib/systemd/system/imap4s.service /usr/lib/systemd/system/imap4.service /usr/lib/systemd/system/pop3s.service

cat "$SC_INSTALL_DIR/modules/perdition/services/imap4s.service" > /etc/systemd/system/imap4s.service
cat "$SC_INSTALL_DIR/modules/perdition/services/imap4.service" > /etc/systemd/system/imap4.service
cat "$SC_INSTALL_DIR/modules/perdition/services/pop3s.service" > /etc/systemd/system/pop3s.service

systemctl daemon-reload

add_service imap4
add_service imap4s
add_service pop3s



