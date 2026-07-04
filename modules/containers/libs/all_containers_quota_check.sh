#!/bin/bash

SIZE_LIMIT=250000000;

function all_containers_quota_check() { ## cmd
    local list host size quota
    
    if $SC_UID0
    then
        list="$(get cluster container_list)" || exit 15
    else
        list="$(cfg user container_list)" || exit 15
    fi
    
    for C in $list
    do
        if [[ -d /srv/$C ]]
        then
        	size="$(du -s /srv/$C | awk '{print $1;}')"
        
            msg "$C $size"
            
            put container "$C" du "$size"
            
            quota="$(get container "$C" quota)"
            
            if (( size > quota ))
            then
            	ntc "STOPPING $C SIZE $size IS OVER $quota"
                
                systemctl disable "srvctl-nspawn@$C" --no-pager
                systemctl stop "srvctl-nspawn@$C" --no-pager
                
            fi
            
        fi
        
    done
}
