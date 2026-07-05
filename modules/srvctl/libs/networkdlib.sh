#!/bin/bash

##
##   systemd-networkd host configuration, called by the containers module's
##   pre-update-install-host hook (i.e. part of every host update-install).
##   networkd_configure_interface writes /etc/systemd/network/IFACE.network
##   (static for the datastore-defined primary interface, DHCP otherwise);
##   networkd_configuration iterates the firewalld interface list, switches
##   DNS resolution to systemd-resolved, enables networkd/resolved, DISABLES
##   NetworkManager, and gates each step on a ping to 8.8.8.8.
##

function networkd_configure_interface {

    local f interface host_ip gateway prefix dns1 dns2 primary_interface
    interface="$1"
    
    f="/etc/systemd/network/$interface.network"
    
    if [[ -f $f ]]
    then
        ntc "interface $interface is already configured. Skipping."
        return
    fi
    
    
    msg "Configure interface $interface"
    
    {
        primary_interface="$(get host "$HOSTNAME" interface)";
        host_ip="$(get host "$HOSTNAME" host_ip)"
        gateway="$(get host "$HOSTNAME" gateway)"
        prefix="$(get host "$HOSTNAME" prefix)"
        dns1="$(get host "$HOSTNAME" dns1)"
        dns2="$(get host "$HOSTNAME" dns2)"
    } 2> /dev/null
    
    if [[ -n $host_ip ]] && [[ -n $gateway ]] && [[ -n $prefix ]] && [[ -n $primary_interface ]] && [[ $interface == "$primary_interface" ]]
    then

        msg "Configure primary interface $interface based on srvctl settings"


cat > "$f" << EOF
[Match]
Name=$interface

[Network]
Address=$host_ip/$prefix
Gateway=$gateway
EOF
        
        if [[ -n $dns1 ]]
        then
            echo "DNS=$dns1" >> "$f"
        fi
        
        if [[ -n $dns2 ]]
        then
            echo "DNS=$dns2" >> "$f"
        fi
        
    else
        msg "Configure $interface with DHCP."
        
    cat > "$f" << EOF
[Match]
Name=$interface

[Network]
DHCP=YES
EOF
        
    fi
    
}

function networkd_configuration {
    
    local interfaces interface
    ## first, guess the primary network interface - which is the first .)
    
    interfaces=$(firewall-cmd --list-interfaces)
    { interface="$(get host "$HOSTNAME" interface)"; } 2> /dev/null || ntc "No interface defined for srvctl."
    
    ## Okay some more clarification on this.
    ## Srvctl controlled hosts should have a public-facing static IP, that is considered to be the primary interface.
    ## This is configured automatically, if the interface name matches the
    ## datastore-defined interface of this host (see networkd_configure_interface).


    msg "Network interfaces-list: $interfaces"

    [[ $interface ]] && msg "Srvctl interface: $interface"

    for i in $interfaces
    do
        networkd_configure_interface "$i"
    done


    if [[ "$(systemctl is-active systemd-networkd)" == active ]] && [[ "$(systemctl is-active systemd-resolved)" == active ]]
    then
        msg "systemd-network configuration seems OK"
    else
        ## Recommended way for DNS resolution with systemd
        run rm -f /etc/resolv.conf
        run ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
        
        run systemctl enable systemd-networkd
        run systemctl start systemd-networkd
        run systemctl status systemd-networkd --no-pager
        
        run systemctl enable systemd-resolved
        run systemctl start systemd-resolved
        run systemctl status systemd-resolved --no-pager
        
        if [[ "$(systemctl is-active systemd-networkd)" == active ]] && [[ "$(systemctl is-active systemd-resolved)" == active ]]
        then
            msg "systemd-networkd configuration successful"
        else
            err "systemd-networkd configuration failed. Exiting for now."
            ## FIXME(v4): bare 'exit' after err exits with status 0, so the
            ## caller cannot detect this failure (same at the two exits below).
            exit
        fi
    fi
    
    run networkctl list --no-pager
    run networkctl status --no-pager
    
    if ping 8.8.8.8 -c 1
    then
        msg "Network Connection is up so far."
    else
        err "No network connection at the moment. Exiting for now."
        exit
    fi
    
    if [[ "$(systemctl is-active NetworkManager)" == active ]]
    then
        ntc "NetworkManager is active, stopping / disabling it"
        run systemctl disable NetworkManager
        run systemctl stop NetworkManager
    fi
    
    if ping 8.8.8.8 -c 1
    then
        msg "Network Connection is OK"
    else
        err "Network connection lost. Exiting for now."
        exit
    fi
}

