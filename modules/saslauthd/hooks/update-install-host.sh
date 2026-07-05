#!/bin/bash

## Host install/update hook (run_hooks update-install-host, from the
## update-install command). Installs cyrus-sasl and deploys the saslauthd
## configuration for SMTP AUTH:
##   - /etc/sasl2/smtpd.conf          (postfix SASL settings, generated inline)
##   - /etc/sysconfig/saslauthd       (from this module's conf/ template)
##   - saslauthd.service unit file    (from this module's services/ dir)
## then enables and restarts the service via add_service.

run dnf -y install cyrus-sasl

msg "Installing saslauthd - binary for x86_64"

{
    echo "pwcheck_method: saslauthd"
    echo "mech_list: LOGIN"

} > /etc/sasl2/smtpd.conf

## History: saslauthd <= 2.1.26 was incompatible with perdition, so a patched
## binary (still vendored in this module's bin/ dir) used to be copied over
## /usr/sbin/saslauthd here — no longer needed with current cyrus-sasl.

run saslauthd -v

#TODO check this, if it was successful?

cat "$SC_INSTALL_DIR/modules/saslauthd/conf/saslauthd.conf" > /etc/sysconfig/saslauthd

## FIXME(v4): unit is written to the RPM-owned path /usr/lib/systemd/system/,
## so any dnf update of cyrus-sasl silently reverts it; should live in
## /etc/systemd/system/ (or a drop-in).
cat "$SC_INSTALL_DIR/modules/saslauthd/services/saslauthd.service" > /usr/lib/systemd/system/saslauthd.service

add_service saslauthd

## FIXME(v4): daemon-reload runs after add_service has already enabled and
## restarted the unit, so the first restart after a unit-file change can use
## the stale in-memory definition; reload before add_service.
run systemctl daemon-reload
