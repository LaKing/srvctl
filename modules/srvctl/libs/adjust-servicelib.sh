#!/bin/bash

##
##   service_action SERVICE OP [XSWITCH] — the systemctl mapping behind the
##   default command (command.sh), also called by containers status/update-ve
##   and the openvpn adjust-service hook. Semantics (preserve!):
##     status            -> systemctl status -n 30
##     (empty op)        -> journalctl -u SERVICE --since yesterday
##     start|restart|enable -> systemctl enable + restart + status
##     kill              -> systemctl kill + status
##     stop|disable      -> (disable only for op=disable) + stop + status
##   Non-status ops need root, --user, or wheel membership (else return 66);
##   an unknown op returns 223.
##

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
        
        
        # if root privileges given at start - or --user switch used, or user is in wheel
        if $SC_UID0 || [[ -n "$xswitch" ]] || groups | grep wheel > /dev/null
        then

            ## yea, in sc we use simplified operations, use systemd for specific ops
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
