#!/bin/bash

[ "$ID" == fedora ] || return;


function sc_install {
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    #run dnf -y -q --releasever "$VERSION_ID" install $*
    run dnf -y -q install $*
    
}

function sc_update {
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    run dnf -y --releasever "$VERSION_ID" update $*
}

function msg_version_installed {
    ## by package manager
    local i v info
    if info="$(dnf info installed "$1" 2> /dev/null)"
    then
        v=$(echo "$info" | grep -m1 Version)
        i=$(echo "$info" | grep -m1 installed)
        msg "$1 ${v:13:8} ${i:13}"
    else
        ntc "$1 not installed"
    fi
}

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

