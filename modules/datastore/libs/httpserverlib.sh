#!/bin/bash

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

[Install]
WantedBy=multi-user.target
    " > /etc/systemd/system/datastore-server.service
    
    #/lib/systemd/system/
    
    systemctl daemon-reload
    
    run systemctl enable datastore-server.service
    run systemctl start datastore-server.service
    run systemctl status datastore-server.service --no-pager
}
