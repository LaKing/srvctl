#!/bin/bash

## Postfix mail, incoming and outgoing on hosts and containers

msg "Installing postfix."

sc_install postfix
sc_install amavisd-new

## deal with certificates
install_service_hostcertificate /etc/perdition

cat "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" > /etc/postfix/main.cf

if [ -f /etc/postfix/ca-bundle.pem ]
then
    echo "smtpd_tls_CAfile =    /etc/postfix/ca-bundle.pem" >> /etc/postfix/main.cf
fi

echo "smtpd_sasl_local_domain = $SC_COMPANY_DOMAIN" >> /etc/postfix/main.cf

cat "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" > /etc/postfix/master.cf

add_service postfix
add_service amavisd

make_aliases_db ''

firewalld_add_service smtp
firewalld_add_service smtps

