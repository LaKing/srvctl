#!/bin/bash

##
##   modules/postfix/hooks/update-install-host.sh — install the mail hub.
##
##   Runs via 'run_hooks update-install-host' from 'sc update-install' on
##   a farm host. Postfix mail, incoming and outgoing, for the host and
##   its containers: installs the packages, deploys the TLS host
##   certificate into /etc/postfix (crt.pem/key.pem, optionally
##   ca-bundle.pem — certificates module), renders main.cf/master.cf from
##   this module's conf/ templates, enables+restarts the three services,
##   and rebuilds /etc/aliases.
##

msg "Installing postfix."

sc_install spamassassin
sc_install postfix
sc_install amavisd-new

## deal with certificates
install_service_hostcertificate /etc/postfix

## host main.cf: template plus two appended settings — the CA bundle path
## (only when the certificate install produced one) and the SASL domain
cat "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" > /etc/postfix/main.cf

if [[ -f /etc/postfix/ca-bundle.pem ]]
then
    echo "smtpd_tls_CAfile =    /etc/postfix/ca-bundle.pem" >> /etc/postfix/main.cf
fi

echo "smtpd_sasl_local_domain = $SC_COMPANY_DOMAIN" >> /etc/postfix/main.cf

cat "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" > /etc/postfix/master.cf

add_service postfix
add_service amavisd
add_service spamassassin

## FIXME(v4): low — rewrites host /etc/aliases from the static template
## on every update-install, silently destroying locally added aliases
## (e.g. a root: forward).
make_aliases_db ''
