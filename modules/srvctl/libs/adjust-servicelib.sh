#!/bin/bash

function service_action {
    
    local service="$1"
    local op="$2"
    local xswitch=''
    
    if [[ ! -z "$3" ]]
    then
        xswitch="$3"
    fi
    
    if [[ $op == "status" ]]
    then
        run systemctl status "$service" "$xswitch" --no-pager -n 30
        return 0
    else
        
        if $SC_ROOT || [[ ! -z "$3" ]]
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
            
            
            if [[ $op == "stop" ]] || [[ $op == "disable" ]] || [[ $op == "kill" ]]
            then
                [[ $op == "disable" ]] && run systemctl disable "$service" "$xswitch"
                run systemctl stop "$service" "$xswitch"
                [[ $op == "kill" ]] && run systemctl kill "$service" "$xswitch" --no-pager
                run systemctl status "$service" "$xswitch" --no-pager -n 30
                return 0
            fi
            
            ## there was no op??
            return 223
            
        else
            err "AUTH start|stop|kill|restart(enable|remove) service operations need root privileges."
            return 66
        fi
        
    fi
}
