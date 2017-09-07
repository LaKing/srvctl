#!/bin/bash

function install_acme {
    
    msg "Installing letsencryppt and the acme-server"
    
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

[Install]
WantedBy=multi-user.target
    " > /etc/systemd/system/acme-server.service
    
    ## TODO remove
    rm -fr /lib/systemd/system/acme-server.service
    
    cat "$SC_INSTALL_DIR/modules/letsencrypt/letsencrypt-ca.pem" > /etc/letsencrypt/ca.pem
    
    systemctl daemon-reload
    
    
    run systemctl enable acme-server.service
    run systemctl start acme-server.service
    run systemctl status acme-server.service --no-pager
}


function regenerate_letsencrypt {
    
    if [ "$(systemctl is-active pound.service)" != "active" ]
    then
        err "Pound is not running!"
        systemctl status pound.service --no-pager
        
        exit 99
    fi
    
    if [ "$(systemctl is-active acme-server.service)" != "active" ]
    then
        err "Acme server is not running!"
        systemctl status acme-server.service --no-pager
        
        exit 98
    fi
    
    mkdir -p "$SC_DATASTORE_DIR/cert"
    mkdir -p /etc/letsencrypt/live
    
    msg "Regenerate letsencrypt certificates"
    letsencrypt_main
    
}
