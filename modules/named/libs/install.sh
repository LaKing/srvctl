#!/bin/bash

function install_named {
    
    msg "Installing bind/named DNS server."
    
    source "$SC_INSTALL_DIR/modules/named/installnamedlib.sh"
    ### procedures defined, now back to running code
    
    [[ -f /usr/sbin/named ]] || sc_install bind bind-utils
    [[ -f /usr/sbin/ntpd ]] || sc_install ntp
    
    run systemctl enable ntpd
    run systemctl start ntpd
    
    ## configure DNS server
    ## no recursion to prevent DNS amplifiaction attacks
    
    mkdir -p /var/srvctl3/named
    
    msg "Configure BIND"
    ## DNS needs NTPD enabled and running, otherwise queries may get no response.
    
    procedure_write_etc_named_conf
    
    echo "## $SRVCTL generated" > "/var/named/named.conf.local"
    
    rsync -a /usr/share/doc/bind/sample/etc/named.rfc1912.zones /etc
    rsync -a /usr/share/doc/bind/sample/var/named /var
    mkdir -p /var/named/dynamic
    mkdir -p /var/named/srvctl
    
    chown -R named:named /var/named #?/srvctl
    chmod 750 /var/named/srvctl
    
    regenerate_named_conf
    
    add_service named
    firewalld_add_service dns
    
    
}

function install_dyndns {
    
    ## dyndns stuff
    ntc "dyndns implementation not ready"
    return
    
    ## TODO dyndns should be really node user?
    
    if [[ -f /etc/srvctl/cert/"$CDN/$CDN".key ]] && [[ -f /etc/srvctl/cert/"$CDN/$CDN".crt ]]
    then
        
        if [[ ! -f /etc/systemd/system/dyndns-server.service ]]
        then
            log "Installing BIND based dyndns."
            
            mkdir -p /var/dyndns
            chown node:root /var/dyndns
            chmod 754 /var/dyndns
            
            procedure_write_dyndns_server_service
            
            systemctl daemon-reload
            systemctl enable dyndns-server
            systemctl start dyndns-server
        fi
        
        if [ ! -d /var/named/keys ]
        then
            local _this key
            
            mkdir -p /var/named/keys
            _this="$(dnssec-keygen -K /var/named/keys -r /dev/urandom -a HMAC-MD5 -b 512 -n USER srvctl)"
            cat "/var/named/keys/$_this.key" > /var/named/keys/srvctl.key
            cat "/var/named/keys/$_this.private" > /var/named/keys/srvctl.private
            
            chown node /var/dyndns/srvctl.private
            chmod 400 /var/dyndns/srvctl.private
            
            key="$(grep 'Key: ' "/var/named/keys/$_this.private")"
            
            procedure_write_named_srvctl_include_key_conf "$key"
            
            
            ## use it in dyndns-server
            cat /var/named/srvctl-include-key.conf > /var/dyndns/srvctl-include-key.conf
            chown node:node /var/dyndns/srvctl-include-key.conf
            chmod 400 /var/dyndns/srvctl-include-key.conf
            
            ## named needs to write to these folders for dyndns
            chown -R named:named /var/named #?/srvctl
            chmod 750 /var/named/srvctl
        fi
        
    else
        msg "Skipping install for dyndns server due to a lack of certificates: /etc/srvctl/cert/$CDN/$CDN.key /etc/srvctl/cert/$CDN/$CDN.crt"
    fi
    
}

