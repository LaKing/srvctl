#!/bin/bash

##
##   modules/perdition/libs/install_perdition.sh — perdition module
##   lib, auto-loaded when the module is enabled.
##
##   install_perdition installs the perdition package, the host
##   certificate, /etc/perdition/perdition.conf (from conf/), the
##   /var/perdition map dir, and the three custom systemd units
##   (imap4, imap4s, pop3s), then generates the routing map and
##   enables the services. CURRENTLY HAS NO CALLER: its only call
##   site is commented out in hooks/update-install-host.sh — the
##   module is half-abandoned in v3, slated to be replaced by the G9
##   mail proxy in v4.
##

function install_perdition {

    ## Perdition mail reverse proxy: routes IMAP4/IMAP4S/POP3S clients
    ## to the per-domain mail.<domain> container's dovecot.

    msg "Installing perdition. Custom service files are: imap4.service, imap4s.service, pop3s.service"

    sc_install perdition

    ## TODO add wildcard certificate for CDN

    install_service_hostcertificate /etc/perdition

    cat "$SC_INSTALL_DIR/modules/perdition/conf/perdition.conf" > /etc/perdition/perdition.conf

    ## it seems to be unnecessary
    if [[ -f /etc/perdition/ca-bundle.pem ]]
    then
        echo "#ssl_ca_chain_file = /etc/perdition/ca-bundle.pem" >> /etc/perdition/perdition.conf
    fi

    ## FIXME(v4): low — this /etc/perdition/popmap.re seed is never
    ## read or updated: perdition.conf points map_library_opt at
    ## /var/perdition/popmap.re (the live map written by perditioncfg).
    echo "#### srvctl tuned popmap.re" > /etc/perdition/popmap.re
    ## popmap.re needs to be generated

    mkdir -p /var/run/perdition
    mkdir -p /var/perdition

    perditioncfg

    ## install services

    ## FIXME(v4): low — removes RPM-owned unit files; any perdition
    ## package update restores them (harmless only because the /etc
    ## copies below take precedence, but it breaks rpm -V).
    rm -fr /usr/lib/systemd/system/imap4s.service /usr/lib/systemd/system/imap4.service /usr/lib/systemd/system/pop3s.service

    cat "$SC_INSTALL_DIR/modules/perdition/services/imap4s.service" > /etc/systemd/system/imap4s.service
    cat "$SC_INSTALL_DIR/modules/perdition/services/imap4.service" > /etc/systemd/system/imap4.service
    cat "$SC_INSTALL_DIR/modules/perdition/services/pop3s.service" > /etc/systemd/system/pop3s.service

    systemctl daemon-reload

    add_service imap4
    add_service imap4s
    add_service pop3s

}
