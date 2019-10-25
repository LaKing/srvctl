#!/bin/bash

function regenerate_etc_postfix_relaydomains() {
    if [[ -d /etc/postfix/ ]]
    then
        get cluster postfix_relaydomains > /etc/postfix/relaydomains
        postmap /etc/postfix/relaydomains
    fi
}

function write_ve_postfix_conf { #container
    local container
    container="$1"
    
    if [[ "${container:0:5}" == "mail." ]]
    then
        msg "write postfix for mail container"
        write_ve_postfix_main "${container:5}"
        write_ve_postfix_main "$container"
    else
        msg "write postfix for container"
        write_ve_postfix_main "$container"
        write_ve_postfix_main "mail.$container"
    fi
}


function write_ve_postfix_main { #container
    local container conf
    container="$1"
    
    if [[ ! -d /srv/$container ]]
    then
        return 0
    fi
    
    
    if [[ $(get container "$container" exist) == true ]]
    then
        msg "Writing postfix configuration for $container"
        
        conf="/srv/$container/rootfs/etc/postfix/main.cf"
        
        if [[ ! -f $conf ]]
        then
            err "$conf does not exist"
        else
            cat "$conf" >> "/srv/$container/rootfs/etc/postfix/main.cf-$NOW.bak"
        fi
        
        if [[ "${container:0:5}" == "mail." ]]
        then
            cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-mail.cf" > "$conf"
        else
            cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-main.cf" > "$conf"
        fi
    else
        err "$container dont exists"
    fi
}

## to be used inside containers
function write_postfix_main {
    local container conf
    
    container="$HOSTNAME"
    conf="/etc/postfix/main.cf"
    
    msg "Writing posfix configuration in $container "
    
    if [[ ! -f $conf ]]
    then
        err "$conf does not exist"
    else
        cat "$conf" >> "/etc/postfix/main.cf-$NOW.bak"
    fi
    
    if [[ "${container:0:5}" == "mail." ]]
    then
        cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-mail.cf" > "$conf"
    else
        cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-main.cf" > "$conf"
    fi
    
    run systemctl restart postfix
}
