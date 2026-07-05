#!/bin/bash

##
##   letsencrypt/libs/letsencryptlib.sh — acme install and regenerate driver.
##
##   Sourced by load_libs whenever the letsencrypt module is enabled.
##   Provides:
##     install_acme            — update-install-host hook payload
##     regenerate_letsencrypt  — regenerate_certificates hook payload
##
##   Touches /etc/letsencrypt/{cli.ini,ca.pem,live/}, /var/acme (challenge
##   webroot, owned acme:acme, uid 528), /etc/systemd/system/
##   acme-server.service and $SC_DATASTORE_DIR/cert/. The unit name
##   acme-server.service, the acme user, the /var/acme webroot and the
##   server's port 1028 are shared API: haproxy forwards the port-80
##   /.well-known/acme-challenge/ path to 127.0.0.1:1028.
##

## install_acme: one-shot host setup for the ACME http-01 workflow.
## Installs the certbot package (sc_install letsencrypt), writes
## /etc/letsencrypt/cli.ini (webroot authenticator on /var/acme), creates
## the acme system user and webroot, generates and starts
## acme-server.service (the port-1028 challenge responder behind haproxy)
## and installs the vendored CA to /etc/letsencrypt/ca.pem. Runs on every
## update-install (twice, in fact — the certificates module hook also calls
## it); re-runs only regenerate the same files.
function install_acme {

    msg "Installing letsencrypt and the acme-server"

    ## install letsencrypt
    sc_install letsencrypt
    mkdir -p /etc/letsencrypt

    echo "## $SRVCTL generated
email = webmaster@$SC_COMPANY_DOMAIN
text = True
authenticator = webroot
webroot-path = /var/acme
    " > /etc/letsencrypt/cli.ini

    mkdir -p /var/acme
    ## FIXME(v4): useradd is unguarded — on re-install it prints
    ## "useradd: user 'acme' already exists" on stderr (non-fatal noise);
    ## guard with getent/id or wrap in eyif.
    useradd -r -u 528 -c "Letsencrypt-acme-server" acme
    chown acme:acme /var/acme

    echo "## $SRVCTL generated
[Unit]
Description=Letsencrypt server.
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node $SC_INSTALL_DIR/modules/letsencrypt/apps/acme-server.js
User=acme
Group=acme

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
    " > /etc/systemd/system/acme-server.service

    ## cleanup of the legacy unit location. TODO remove
    rm -fr /lib/systemd/system/acme-server.service

    ## FIXME(v4): the vendored letsencrypt-ca.pem is DST Root CA X3,
    ## expired 2021-09-30. letsencrypt.js appends /etc/letsencrypt/ca.pem to
    ## every deployed bundle, so all bundles ship an expired root — drop the
    ## append or vendor the current ISRG root in the DNS-01 redesign.
    cat "$SC_INSTALL_DIR/modules/letsencrypt/letsencrypt-ca.pem" > /etc/letsencrypt/ca.pem

    systemctl daemon-reload

    run systemctl enable acme-server.service
    run systemctl start acme-server.service
    run systemctl status acme-server.service --no-pager
}


## regenerate_letsencrypt: regenerate_certificates hook payload. Makes sure
## acme-server.service is running (http-01 challenges would fail without
## it), prepares $SC_DATASTORE_DIR/cert and /etc/letsencrypt/live, then
## runs letsencrypt.js over all container domains (letsencrypt_main,
## bashlib.sh). Errors out without running anything when the service
## cannot be started.
function regenerate_letsencrypt {

    if [[ "$(systemctl is-active acme-server.service)" != "active" ]]
    then
        run systemctl enable acme-server.service
        run systemctl start acme-server.service
        run systemctl status acme-server.service --no-pager
    fi

    if [[ "$(systemctl is-active acme-server.service)" == "active" ]]
    then

        mkdir -p "$SC_DATASTORE_DIR/cert"
        mkdir -p /etc/letsencrypt/live

        msg "Regenerate letsencrypt certificates"
        letsencrypt_main
    else

        err "Acme server is not running! "
        systemctl status acme-server.service --no-pager

    fi
}
