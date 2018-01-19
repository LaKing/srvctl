#!/bin/bash

function all_containers_execute() { ## cmd
    local list host cmd temp_file
    cmd="$1"
    
    msg "Command is: $cmd"
    
    if [[ $SC_USER == root ]]
    then
        list="$(cfg cluster container_list)" || exit 15
    else
        list="$(cfg user container_list)" || exit 15
    fi
    
    for C in $list
    do
        if [[ -d /srv/$C ]]
        then
            msg "$HOSTNAME / $C"
            
            if systemctl is-active srvctl-nspawn@"$C" >/dev/null 2>&1
            then
                ## this is a solution .. direct call causes some shell weirdness
                say machinectl -q --no-pager shell "$C" "/bin/bash/ -c '$cmd'"
                temp_file=$(mktemp)
                echo "machinectl -q --no-pager shell $C /bin/bash/ -c '$cmd'" > "$temp_file"
                /bin/bash "$temp_file"
                rm -fr "$temp_file"
            else
                err "Container $C is inactive"
            fi
        else
            host="$(get container "$C" host)"
            msg "$host / $C"
            
            if ssh "$host" systemctl is-active srvctl-nspawn@"$C" >/dev/null 2>&1
            then
                run "ssh $host srvctl $C $cmd"
            else
                err "Container $C is inactive on $host"
            fi
            
        fi
        
    done
}
