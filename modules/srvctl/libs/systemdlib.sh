#!/bin/bash

##
##   add_service NAME / rm_service NAME — enable+restart (or disable+stop) a
##   systemd service and register it by symlink under /etc/srvctl/system/
##   (a write-only registry: nothing in the repo reads it back, but it is an
##   external convention). add_service is used by postfix, mariadb, named,
##   opendkim, perdition, nfs, saslauthd, wordpress; rm_service is unused.
##   FIXME(v4): byte-identical duplicates also live in libs/fedoralib.sh;
##   these copies win because systemdlib sorts later — collapse in v4.
##

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
    
    if [[ -f /usr/lib/systemd/system/$1.service ]] || [[ -f /etc/systemd/system/$1.service ]]
    then
        msg "rm_service $1.service"
        
        rm -rf "/etc/srvctl/system/$1.service" 2> /dev/null
        
        systemctl disable "$1.service"
        systemctl stop "$1.service"
        
        return 0
    fi
    
    err "No such service - $1 (rm_service)"
}
