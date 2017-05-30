#!/bin/bash

function install_acme {
    
    msg "Installing letsencryppt and the acme-server"
    
    ## install letsencrypt
    sc_install letsencrypt
    mkdir -p /etc/letsencrypt
    
    echo '## srvctl generated
email = webmaster@'$SC_COMPANY_DOMAIN'
text = True
authenticator = webroot
webroot-path = /var/acme
    ' > /etc/letsencrypt/cli.ini
    
    mkdir -p /var/acme
    useradd -r -u 528 -c "Letsencrypt-acme-server" acme
    chown acme:acme /var/acme
    
    echo '## srvctl generated
[Unit]
Description=Letsencrypt server.
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node '$SC_INSTALL_DIR'/modules/certificates/acme-server.js
User=acme
Group=acme

[Install]
WantedBy=multi-user.target
    ' > /lib/systemd/system/acme-server.service
    
    cat "$SC_INSTALL_DIR/modules/certificates/letsencrypt-ca.pem" > /etc/letsencrypt/ca.pem
    
    systemctl daemon-reload
    
    
    run systemctl enable acme-server.service
    run systemctl start acme-server.service
    run systemctl status acme-server.service --no-pager
}
