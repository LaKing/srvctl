#!/bin/bash

function service_action {
    local service="$1"
    local op="$2"
    if [[ $op == "status" ]]
    then
        run systemctl status "$service"  --no-pager -n 30
        return 0
    else
        
        if $SC_ROOT
        then
            
            ## yea, in sc we use simplified operations, use systemd for speceific ops
            if [[ $op == "start" ]] || [[ $op == "restart" ]] || [[ $op == "enable" ]]
            then
                run systemctl enable  "$service"
                run systemctl restart "$service"
                sleep 1
                run systemctl status "$service"  --no-pager -n 30
                return 0
            fi
            
            
            if [[ $op == "stop" ]] || [[ $op == "disable" ]] || [[ $op == "kill" ]]
            then
                [[ $op == "disable" ]] && run systemctl disable "$service"
                run systemctl stop "$service"
                [[ $op == "kill" ]] && run systemctl kill "$service"  --no-pager
                run systemctl status "$service"  --no-pager -n 30
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
