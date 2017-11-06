#!/bin/bash

function regenerate_etc_postfix_relaydomains() {
    if [[ -d /etc/postfix/ ]]
    then
        cfg cluster postfix_relaydomains
        postmap /etc/postfix/relaydomains
    fi
}

function write_ve_postfix_conf { #container
    local container
    container="$1"
    
    if [[ "${container:0:5}" == "mail." ]]
    then
        write_ve_postfix_main "${container:5}"
        write_ve_postfix_main "$container"
    else
        write_ve_postfix_main "$container"
        write_ve_postfix_main "mail.$container"
    fi
}


function write_ve_postfix_main { #container
    local domain container
    container="$1"
    domain="$1"
    
    if get container "$container" exist
    then
        msg "Writing postfic configuration for $container"
        
        if [[ "${container:0:5}" == "mail." ]]
        then
            domain="${container:5}"
        fi
        
        conf="/srv/$container/rootfs/etc/postfix/main.cf"
        
        cat "$conf" >> "/srv/$container/rootfs/etc/postfix/main.cf-$NOW.bak"
        
        cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-main.cf" > "$conf"
        
        ## relayhost - host on the bridge
        echo "relayhost = $(get container "$container" br_host_ip)" >> "$conf"
        
        if get container "$container" mx
        then
            ## mydestination - localhost, localhost.localdomain, - WITH or WITHOUT - $myhostname, container-domain
            echo "mydestination = localhost, localhost.localdomain, $domain, mail.$domain" >> "$conf"
        else
            ## mydestination - localhost, localhost.localdomain, - WITH or WITHOUT - $myhostname, container-domain
            echo "mydestination = localhost, localhost.localdomain" >> "$conf"
        fi
        
        ## myorigin - the domain name or the subdomain
        echo "myorigin = $domain" >> "$conf"
        
    fi
}
