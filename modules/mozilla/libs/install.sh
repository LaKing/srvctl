#!/bin/bash

function install_mozilla_autoconfig {
    
    msg "Installing mozilla autoconfig"
    
    echo "## $SRVCTL generated
[Unit]
Description=Letsencrypt server.
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node $SC_INSTALL_DIR/modules/mozilla/apps/mozilla-autoconfig-server.js
User=root
Group=root

[Install]
WantedBy=multi-user.target
    " > /etc/systemd/system/mozilla-autoconfig.service
    
    ## TODO remove after upgrade
    rm -fr /usr/lib/systemd/system/mozilla-autoconfig.service
    
    systemctl daemon-reload
    
    run systemctl enable mozilla-autoconfig.service
    run systemctl start mozilla-autoconfig.service
    run systemctl status mozilla-autoconfig.service --no-pager
}
