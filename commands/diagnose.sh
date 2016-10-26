#!/bin/bash

hint diagnose "Run a set of diagnostic commands."

complicate diagnose

if [ "$CMD" == diagnose ]
then
    msg "srvctl version $(cat "$SC_INSTALL_DIR/version")"
    
    ( set -o posix ; set ) | egrep "DEBUG=|ARG=|CMD=|OPA=|SC_"
    
    # printenv
    
    echo "Uptime: $(uptime)"
    uname -a
    
    if [ -f /usr/bin/grub2-editenv ] && [ -f /boot/grub2/grub.cfg ]
    then
        msg "Kernel"
        uname -r
        msg "Booting"
        grub2-editenv list
        msg "Available for boot"
        grep ^menuentry /boot/grub2/grub.cfg | cut -d "'" -f2
    fi
    
    for service in /etc/srvctl/system/*
    do
        [[ -e $service ]] || break
        
        if ! systemctl is-active "$service"
        then
            systemctl status "$service" --no-pager
        fi
    done
    
    msg "mail que"
    journalctl -u postfix --since yesterday | grep fatal
    postqueue -p
    
    if [ -f /usr/sbin/firewalld ]
    then
        local zone
        local services
        
        zone=$(firewall-cmd --get-default-zone)
        services=" $(firewall-cmd --zone="$zone" --list-services) "
        
        msg "Firewall $(firewall-cmd --state) - default zone: $zone"
        echo "$services"
        echo ''
        
        msg "Interfaces:"
        interfaces="$(firewall-cmd --list-interfaces)"
        for i in $interfaces
        do
            echo "$i - $(firewall-cmd --get-zone-of-interface="$i")"
            echo ''
        done
    fi
    
    msg "table of processes"
    top -n 1
    msg "shell users"
    w
    
    ok
fi
man_en '
    Set of troubleshooting commands, that include information about:

        srvctl version and variables
        uptime
        system/kernel version
        boot configs
        inactive services listed in srvctl
        postfix fatal errors since yesterday
        the mail que
        firewall settings
        table of processes
        connected shell users

    Notes
        To flush the mail que, use: postqueue -f
        To remove all mail from the mail que use: postsuper -d ALL
'

#fi ## isROOT







