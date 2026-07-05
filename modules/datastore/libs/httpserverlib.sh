#!/bin/bash

##
##   modules/datastore/libs/httpserverlib.sh — datastore-server installer.
##
##   install_datastoreserver, called from hooks/update-install-host.sh,
##   writes /etc/systemd/system/datastore-server.service (running
##   apps/datastore-server.js as root on port 1030, proxied by haproxy for
##   the .well-known ACME and datastore-snapshot paths), reloads systemd
##   and enables + starts the unit. The unit text below is installed
##   verbatim on every host — keep it byte-identical.
##

function install_datastoreserver {

    msg "Installing http datastore server"

    echo "## $SRVCTL generated
[Unit]
Description=Srvctl datastore http server for well known uri.
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node $SC_INSTALL_DIR/modules/datastore/apps/datastore-server.js

User=root
Group=root

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
    " > /etc/systemd/system/datastore-server.service

    systemctl daemon-reload

    run systemctl enable datastore-server.service
    run systemctl start datastore-server.service
    run systemctl status datastore-server.service --no-pager
}
