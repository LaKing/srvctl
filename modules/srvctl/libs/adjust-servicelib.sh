#!/bin/bash

function service_action {
    
    local service="$1"
    local op="$2"
    # extra switches for the commands
    local xswitch=''
    
    if [[ -n "$3" ]]
    then
        xswitch="$3"
    fi
    
    if [[ $op == "status" ]]
    then
        run systemctl status "$service" "$xswitch" --no-pager -n 30
        return 0
    else
        
        if [[ -z "$op" ]]
        then
            run journalctl -u "$service" --since yesterday --no-pager
            return 0
        fi
        
        
        # if root privilegs given at start - or --user switch used, or user is in wheel
        if $SC_UID0 || [[ -n "$xswitch" ]] || groups | grep wheel > /dev/null
        then
            
            ## yea, in sc we use simplified operations, use systemd for speceific ops
            if [[ $op == "start" ]] || [[ $op == "restart" ]] || [[ $op == "enable" ]]
            then
                run systemctl enable  "$service" "$xswitch"
                run systemctl restart "$service" "$xswitch"
                sleep 1
                run systemctl status "$service" "$xswitch" --no-pager -n 30
                return 0
            fi
            
            
            if [[ $op == "kill" ]]
            then
                run systemctl kill "$service" "$xswitch" --no-pager
                run systemctl status "$service" "$xswitch" --no-pager -n 30
                return 0
            fi
            
            if [[ $op == "stop" ]] || [[ $op == "disable" ]]
            then
                [[ $op == "disable" ]] && run systemctl disable "$service" "$xswitch"
                run systemctl stop "$service" "$xswitch"
                run systemctl status "$service" "$xswitch" --no-pager -n 30
                return 0
            fi
            return 223
            
        else
            err "All service operations except status need root privileges."
            return 66
        fi
        
    fi
}
