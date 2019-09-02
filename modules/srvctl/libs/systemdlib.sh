#!/bin/bash

function add_service {
    
    if [[ -f /usr/lib/systemd/system/$1.service ]]
    then
        msg "add_service $1.service"
        
        mkdir -p /etc/srvctl/system
        ln -s "/usr/lib/systemd/system/$1.service" "/etc/srvctl/system/$1.service" 2> /dev/null
        
        systemctl enable "$1.service"
        systemctl restart "$1.service"
        systemctl status "$1.service" --no-pager
        
        return 0
    fi
    
    if [[ -f /etc/systemd/system/$1.service ]]
    then
        msg "add_service $1.service"
        
        mkdir -p /etc/srvctl/system
        ln -s "/etc/systemd/system/$1.service" "/etc/srvctl/system/$1.service" 2> /dev/null
        
        systemctl enable "$1.service"
        systemctl restart "$1.service"
        systemctl status "$1.service" --no-pager
        
        return 0
    fi
    
    err "No such service - $1 (add_service)"
    
}

function rm_service {
    
    if [[ -f /usr/lib/systemd/system/$1.service ]] ||  [[ -f /etc/systemd/system/$1.service ]]
    then
        msg "rm_service $1.service"
        
        rm -rf "/etc/srvctl/system/$1.service" 2> /dev/null
        
        systemctl disable "$1.service"
        systemctl stop "$1.service"
        
        return 0
    fi
    
    err "No such service - $1 (rm_service)"
}
## networkd functions

function networkd_configure_interface {
    
    local f interface host_ip gateway prefix dns1 dns2
    interface="$1"
    
    f="/etc/systemd/network/$interface.network"
    msg "Configure interface $interface"
    host_ip="$(get host "$HOSTNAME" host_ip)"
    gateway="$(get host "$HOSTNAME" gateway)"
    prefix="$(get host "$HOSTNAME" prefix)"
    dns1="$(get host "$HOSTNAME" dns1)"
    dns2="$(get host "$HOSTNAME" dns2)"
    
    if [[ ! -z $host_ip ]] && [[ ! -z $gateway ]] && [[ ! -z $prefix ]]
    then
        
cat > "$f" << EOF
[Match]
Name=$interface

[Network]
Address=$host_ip/$prefix
Gateway=$gateway
EOF
        
        if [[ ! -z $dns1 ]]
        then
            echo "DNS=$dns1" >> "$f"
        fi
        
        if [[ ! -z $dns2 ]]
        then
            echo "DNS=$dns2" >> "$f"
        fi
        
    else
        
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
    interface="$(get host "$HOSTNAME" interface)"
    
    msg "Network intefaces: $interfaces"
    
    for i in $interfaces
    do
        if [[ $interface == "$i" ]]
        then
            msg "Configure $i"
            networkd_configure_interface "$i"
        else
            ntc "$i is a secondary interface"
        fi
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
    fi
    
    run networkctl list --no-pager
    run networkctl status --no-pager
    
    if [[ "$(systemctl is-active NetworkManager)" == active ]] #&& [[ -z "$(networkctl | grep 'en' | grep ether | grep routable | grep unmanaged)" ]]
    then
        ntc "NetworkManager is active, stoping / disabling it"
        run systemctl disable NetworkManager
        run systemctl stop NetworkManager
    fi
    
    
}

