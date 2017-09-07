#!/bin/bash

function regenerate_opendkim {
    
    msg "regenerate opendkim"
    
    mkdir -p "$SC_DATASTORE_DIR/opendkim"
    chmod 000 "$SC_DATASTORE_DIR/opendkim"
    mkdir -p /var/opendkim
    
    opendkim_main
    
    if ! diff -rq /var/opendkim "$SC_DATASTORE_DIR/opendkim" > /dev/null
    then
        msg "Updating $HOSTNAME opendkim runtime configuration"
        rm -fr /var/opendkim
        cp -R "$SC_DATASTORE_DIR/opendkim" /var
        chown -R opendkim:opendkim /var/opendkim
        chmod -R 750 /var/opendkim
        chmod 640 /var/opendkim/*/*
        chmod 640 /var/opendkim/KeyTable
        chmod 640 /var/opendkim/SigningTable
        chmod 640 /var/opendkim/TrustedHosts
        
        restart_opendkim
    else
        
        if [ "$(systemctl is-active opendkim.service)" != "active" ]
        then
            msg "Configuration for opendkim is up-to-date."
            err "opendkim.service is not running!"
            run systemctl start opendkim
            run systemctl enable opendkim
            run systemctl status opendkim --no-pager
        else
            msg "Configuration for opendkim is up-to-date, opendkim.service running"
        fi
    fi
}
