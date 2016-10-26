#!/bin/bash

complicate update-install
hint update-install "Run the installation/update script."


## first, update the system
if [[ "$CMD" == update-install ]]
then
    
    sc_update
    
    ## install mc if we dont have it
    [[ -f /bin/mc ]] || sc_install mc
    
    
    if $SC_ON_HS
    then
        
        msg "Containerfarm host installation"
        ## disable selinux
        echo 'SELINUX=disabled' > /etc/selinux/config
        ## TODO enable it when we are there
        
        ## network configuration
        systemctl is-active network && ntc 'network.service is active'
        systemctl is-active NetworkManager && ntc 'NetworkManager is active'
        
        systemctl enable systemd-networkd
        systemctl start systemd-networkd
        
        msg "It is recommended to create systemd-networkd configurations for ethernet cards."
        networkctl | grep ' en' | grep ether | grep routable | grep unmanaged
        
        sc_install systemd-container
        
        ## CREATE BASE IMAGES
        
        ## Recommended way for DNS resolution with systemd
        rm -f /etc/resolv.conf
        ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
        systemctl enable systemd-resolved
        systemctl start systemd-resolved
        
    fi
    
    
    ok
    
fi

man_en '
    Install all components
'
