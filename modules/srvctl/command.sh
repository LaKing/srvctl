#!/bin/bash

## @@@ SERVICE OP | OP SERVICE
## @en OP is one of status|start|stop|kill|restart|enable|remove, SERVICE is a systemd service

## &en This is a shorthand syntax for frequent operations on systemd.
## &en the following are equivalent:
## &en         systemctl status example.service
## &en         sc example ?
## &en to query a service with the supershort operator "?" or with "status"
## &en to restart and enable a service the operator is "!" or "restart"
## &en to start and enable a service the operator is "+" or "start"
## &en to stop and disable a service the operator is "-" or "stop"

## this is a special command, as it has several ways to be invoked

#### these specs are used in the gui
## spec //services×start×start a service×start SERVICE
## spec //services×stop×stop a service×stop SERVICE
## spec //services×restart×restart a service×restart SERVICE
## spec //services×status×status of a service×status SERVICE
## spec //services×kill×kill a service×kill SERVICE

## adjust-service
if [[ $ARG == enable ]] || [[ $ARG == start ]] || [[ $ARG == restart ]] || [[ $ARG == stop ]] || [[ $ARG == status ]]  || [[ $ARG == disable ]] || [[ $ARG == kill ]] \
|| [[ $CMD == enable ]] || [[ $CMD == start ]] || [[ $CMD == restart ]] || [[ $CMD == stop ]] || [[ $CMD == status ]]  || [[ $CMD == disable ]] || [[ $CMD == kill ]]
then
    
    op=''
    service=''
    
    ## fix op/service ordering
    if [[ $ARG == "enable" ]] || [[ $ARG == "start" ]] || [[ $ARG == "restart" ]] || [[ $ARG == "stop" ]] || [[ $ARG == "status" ]] || [[ $ARG == "disable" ]] || [[ $ARG == "kill" ]]
    then
        op=$ARG
        service=$CMD
    fi
    
    ## its the other way around
    if [[ $CMD == "enable" ]] || [[ $CMD == "start" ]] || [[ $CMD == "restart" ]] || [[ $CMD == "stop" ]] || [[ $CMD == "status" ]] || [[ $CMD == "disable" ]] || [[ $CMD == "kill" ]]
    then
        op=$CMD
        service=$ARG
    fi
    
    run_hook adjust-service
    
    #[[ $DEBUG == true ]] && ntc "@srvctl-command"
    #ntc "SERVICE: $service OP: $op"
    
    if [[ ! -z "$service" ]] && [[ ! -z "$op" ]]
    then
        #local ok ck xswitch
        
        #if [[ "$(systemctl is-active "$service")" != unknown ]]
        if systemctl is-active "$service" > /dev/null
        then
            ok=true
        else
            ok=false
            ck=''
            xswitch=""
            for i in /usr/lib/systemd/system/* /etc/systemd/system/* /etc/systemd/system/*/* /run/systemd/system/*
            do
                [[ -f "$i" ]] || continue
                #[[ $DEBUG == true ]] && ntc "@ $i"
                ck="$(basename "$i")"
                ## service.service, socket.socket, device.device, mount.mount, automount.automount, swap.swap, target.target, path.path, timer.timer, slice.slice, scope.scope
                if [[ "$ck" == "$i" ]] || [[ "$ck" == "$service.service" ]] || [[ "$ck" == "$service.socket" ]] || [[ "$ck" == "$service.device" ]] || [[ "$ck" == "$service.mount" ]] || [[ "$ck" == "$service.automount" ]] \
                || [[ "$ck" == "$service.swap" ]] || [[ "$ck" == "$service.target" ]] || [[ "$ck" == "$service.path" ]] || [[ "$ck" == "$service.timer" ]] || [[ "$ck" == "$service.slice" ]] || [[ "$ck" == "$service.scope" ]]
                then
                    service="$ck"
                    ok=true
                    ntc "ASSUME system-service: $service"
                    break
                fi
            done
            
            for i in ~/.config/systemd/user/* /etc/systemd/user/* $XDG_RUNTIME_DIR/systemd/user/* /run/systemd/user/* ~/.local/share/systemd/user/* /usr/lib/systemd/user/*
            do
                [[ -f "$i" ]] || continue
                #[[ $DEBUG == true ]] && ntc "@ $i"
                ck="$(basename "$i")"
                ## service.service, socket.socket, device.device, mount.mount, automount.automount, swap.swap, target.target, path.path, timer.timer, slice.slice, scope.scope
                if [[ "$ck" == "$i" ]] || [[ "$ck" == "$service.service" ]] || [[ "$ck" == "$service.socket" ]] || [[ "$ck" == "$service.device" ]] || [[ "$ck" == "$service.mount" ]] || [[ "$ck" == "$service.automount" ]] \
                || [[ "$ck" == "$service.swap" ]] || [[ "$ck" == "$service.target" ]] || [[ "$ck" == "$service.path" ]] || [[ "$ck" == "$service.timer" ]] || [[ "$ck" == "$service.slice" ]] || [[ "$ck" == "$service.scope" ]]
                then
                    xswitch="--user"
                    service="$ck"
                    ok=true
                    ntc "ASSUME user-service: $service"
                    break
                fi
            done
            
        fi
        
        if ! $ok
        then
            err "could not locate '$service' in systemd"
            return 78
        fi
        
        service_action "$service" "$op" "$xswitch"
        exit_0
    fi
    return 0
    #exit 0
fi
