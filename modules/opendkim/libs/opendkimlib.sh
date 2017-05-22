#!/bin/bash

function procedure_get_dkim_p {
    local x
    x="$8"
    p="${x:3: -1}"
}

function regenerate_opendkim {
    
    msg "regenerate opendkim"
    
    mkdir -p /var/opendkim
    
    chmod 750 /var/opendkim
    rm -rf /var/opendkim/*
    # shellcheck disable=SC2129
    echo '127.0.0.1' >> /var/opendkim/TrustedHosts
    echo '::1' >> /var/opendkim/TrustedHosts
    echo "10.0.0.0/8" >> /var/opendkim/TrustedHosts
    echo '' >> /var/opendkim/SigningTable
    echo '' >> /var/opendkim/KeyTable
    
    chmod -R 640 /var/opendkim
    chmod 750 /var/opendkim
    
    local containerlist p
    containerlist="$(cfg system container_list)"
    
    for container in $containerlist
    do
        
        if [[ ! -d "/srv/$container/rootfs" ]]
        then
            continue
        fi
        
        if [ ! -d "/srv/$container/opendkim" ]
        then
            dkim_selector="default"
            if [ "${container:0:5}" == "mail." ]
            then
                dkim_selector="mail"
            fi
            mkdir -p "/srv/$container/opendkim"
            opendkim-genkey -D "/srv/$container/opendkim" -d "$container" -s "$dkim_selector"
        fi
        
        
        if [ "${container: -6}" == "-devel" ] || [ "${container: -6}" == ".devel" ] || [ "${container: -6}" == "-local" ] || [ "${container: -6}" == ".local" ]
        then
            echo 'Skipping' > /dev/null
        else
            
            echo "$container" >> /var/opendkim/TrustedHosts
            
            for i in /srv/"$container"/opendkim/*.private
            do
                selector="$(basename "$i")"
                selector="${selector:0:-8}"
                
                mkdir -p "/var/opendkim/$container"
                chmod 750 "/var/opendkim/$container"
                
                cat "/srv/$container/opendkim/$selector.private" > "/var/opendkim/$container/$selector.private"
                chmod -R 640 "/var/opendkim/$container/$selector.private"
                
                echo "$selector._domainkey.$container $container:$selector:/var/opendkim/$container/$selector.private" >> /var/opendkim/KeyTable
                echo "*@$container $selector._domainkey.$container" >> /var/opendkim/SigningTable
                
                p=''
                str="$(cat "/srv/$container/opendkim/$selector.txt")"
                procedure_get_dkim_p "$str"
                put container "$container" "dkim-$selector-domainkey" "$p"
                
            done
        fi
        
    done
    
    
    restart_opendkim
    
}
