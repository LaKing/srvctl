#!/bin/bash

## @@@ SERVICE OP | OP SERVICE
## @en status / start|stop|kill|restart(enable|remove) a service via systemctl. Shortcuts for OP: ? / +|-|!
## &en Update/Install all components
## &en On host systems install the containerfarm

## &en This is a shorthand syntax for frequent operations on services.
## &en the following are equivalent:
## &en         systemctl status example.service
## &en         sc example ?
## &en to query a service with the supershort operator "?" or with "status"
## &en to restart and enable a service the operator is "!" or "restart"
## &en to start and enable a service the operator is "+" or "start"
## &en to stop and disable a service the operator is "-" or "stop"

local op=''
local service=''

function service_action {
    local service="$1"
    local op="$2"
    if [ "$op" == "status" ]
    then
        run systemctl status "$service"  --no-pager
        return 0
    else
        
        if $SC_ROOT
        then
            
            ## yea, in sc we use simplified operations, use systemd for speceific ops
            if [ "$op" == "start" ] || [ "$op" == "restart" ] || [ "$op" == "enable" ]
            then
                run systemctl enable  "$service"
                run systemctl restart "$service"
                run systemctl status "$service"  --no-pager
            fi
            
            
            if [ "$op" == "stop" ] || [ "$op" == "disable" ] || [ "$op" == "kill" ]
            then
                run systemctl disable "$service"
                run systemctl stop "$service"
                [ "$op" == "kill" ] && run systemctl kill "$service"  --no-pager
                run systemctl status "$service"  --no-pager
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


## fix op/service ordering
if [ "$ARG" == "enable" ] || [ "$ARG" == "start" ] || [ "$ARG" == "restart" ] || [ "$ARG" == "stop" ] || [ "$ARG" == "status" ] || [ "$ARG" == "disable" ] || [ "$ARG" == "kill" ]
then
    op=$ARG
    service=$CMD
fi

## its th eother way around
if [ "$CMD" == "enable" ] || [ "$CMD" == "start" ] || [ "$CMD" == "restart" ] || [ "$CMD" == "stop" ] || [ "$CMD" == "status" ] || [ "$CMD" == "disable" ] || [ "$ARG" == "kill" ]
then
    op=$CMD
    service=$ARG
fi

## special services
if [ "$service" == openvpn ] && [ ! -z "$op" ] && [ -f "/usr/lib/systemd/system/openvpn@.service" ] && $IS_ROOT
then
    
    ## must have conf
    for c in /etc/openvpn/*.conf
    do
        local s="${c:13: -5}"
        msg "$s"
        service_action "openvpn@$s" "$op"
    done
    return 0
fi

if [ ! -z "$service" ] && [ ! -z "$op" ]
then
    
    if [ "$(systemctl is-active "$service")" != unknown ]
    then
        local ok=true
    else
        local ok=false
        local ck=''
        for i in /usr/lib/systemd/system/* /etc/systemd/system/* /run/systemd/system/* ~/.config/systemd/user/* /etc/systemd/user/* $XDG_RUNTIME_DIR/systemd/user/* /run/systemd/user/* ~/.local/share/systemd/user/* /usr/lib/systemd/user/*
        do
            [ -f "$i" ] || continue
            ck="$(basename "$i")"
            ## service.service, socket.socket, device.device, mount.mount, automount.automount, swap.swap, target.target, path.path, timer.timer, slice.slice, scope.scope
            if [ "ck" == "$i" ] || [ "$ck" == "$service.service" ] || [ "$ck" == "$service.socket" ] || [ "$ck" == "$service.device" ] || [ "$ck" == "$service.mount" ] || [ "$ck" == "$service.automount" ] \
            || [ "$ck" == "$service.swap" ] || [ "$ck" == "$service.target" ] || [ "$ck" == "$service.path" ] || [ "$ck" == "$service.timer" ] || [ "$ck" == "$service.slice" ] || [ "$ck" == "$service.scope" ]
            then
                
                service="$ck"
                ok=true
                ntc "ASSUME: $service"
                break
            fi
        done
        
    fi
    
    if ! $ok
    then
        err "could not locate '$service' in systemd"
        return 78
    fi
    
    service_action "$service" "$op"
    
fi





