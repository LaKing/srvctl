#!/bin/bash

## Postfix mail, incoming and outgoing on hosts and containers

msg "Installing postfix."

sc_install postfix
sc install amavisd-new

## deal with certificates
## TODO add wildcard certificate for CDN

cat "/etc/srvctl/cert/$HOSTNAME/$HOSTNAME.pem" > /etc/postfix/crt.pem
cat "/etc/srvctl/cert/$HOSTNAME/$HOSTNAME.key" > /etc/postfix/key.pem

chmod 400 /etc/postfix/crt.pem
chmod 400 /etc/postfix/key.pem


cat "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" > /etc/postfix/main.cf

if [ -f /etc/srvctl/cert/ca-bundle.pem ]
then
    cat /etc/srvctl/cert/ca-bundle.pem > /etc/postfix/ca-bundle.pem
    echo "smtpd_tls_CAfile =    /etc/postfix/ca-bundle.pem" >> /etc/postfix/main.cf
fi

echo "smtpd_sasl_local_domain = $SC_COMPANY_DOMAIN" >> /etc/postfix/main.cf

cat "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" > /etc/postfix/master.cf

add_service postfix
add_service amavisd

make_aliases_db ''

firewalld_add_service smtp
