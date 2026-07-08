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

##
##   Default command handler — sourced by run_command (commonlib.sh) only
##   when no named command matched. Treats the command line as
##   SERVICE OP or OP SERVICE and maps it onto systemctl via service_action
##   (libs/adjust-servicelib.sh). If the unit is not active, the system and
##   user unit directories are scanned for SERVICE with any unit-type suffix
##   appended. When nothing matches, 'return 0' hands control back to the
##   dispatcher, which ends with "Invalid command." and exit 1.
##   Note: the short operators ? ! + - are already mapped to
##   status/restart/start/stop by srvctl.sh before this file runs.
##

op=''
service="$CMD"

## fix op/service ordering
if [[ $ARG == "enable" ]] || [[ $ARG == "start" ]] || [[ $ARG == "restart" ]] || [[ $ARG == "stop" ]] || [[ $ARG == "status" ]] || [[ $ARG == "disable" ]] || [[ $ARG == "kill" ]]
then
    op="$ARG"
    service="$CMD"
fi

## it's the other way around
if [[ $CMD == "enable" ]] || [[ $CMD == "start" ]] || [[ $CMD == "restart" ]] || [[ $CMD == "stop" ]] || [[ $CMD == "status" ]] || [[ $CMD == "disable" ]] || [[ $CMD == "kill" ]]
then
    op="$CMD"
    service="$ARG"
fi

## check additional modules
run_hook adjust-service

if systemctl is-active "$service" > /dev/null
then
    ok=true
else
    ok=false
    ck=''
    xswitch=""
    for i in /usr/lib/systemd/system/* /etc/systemd/system/* /etc/systemd/system/*/* /run/systemd/system/* /run/systemd/transient/*
    do
        [[ -f "$i" ]] || continue
        ck="$(basename "$i")"
        ## service.service, socket.socket, device.device, mount.mount, automount.automount, swap.swap, target.target, path.path, timer.timer, slice.slice, scope.scope
        ## FIXME(v4): '$ck == $i' compares a basename to a full path and is never
        ## true (likely intended '$ck == $service'), so a unit named with its
        ## explicit suffix (e.g. 'sc foo.timer start' while inactive) is never
        ## matched here and falls through to "Invalid command."
        if [[ "$ck" == "$i" ]] || [[ "$ck" == "$service.service" ]] || [[ "$ck" == "$service.socket" ]] || [[ "$ck" == "$service.device" ]] || [[ "$ck" == "$service.mount" ]] || [[ "$ck" == "$service.automount" ]] \
        || [[ "$ck" == "$service.swap" ]] || [[ "$ck" == "$service.target" ]] || [[ "$ck" == "$service.path" ]] || [[ "$ck" == "$service.timer" ]] || [[ "$ck" == "$service.slice" ]] || [[ "$ck" == "$service.scope" ]]
        then
            service="$ck"
            ok=true
            ntc "ASSUME system-service: $service"
            break
        fi
    done
    
    for i in ~/.config/systemd/user/* /etc/systemd/user/* "$XDG_RUNTIME_DIR"/systemd/user/* /run/systemd/user/* ~/.local/share/systemd/user/* /usr/lib/systemd/user/*
    do
        [[ -f "$i" ]] || continue
        ck="$(basename "$i")"
        ## service.service, socket.socket, device.device, mount.mount, automount.automount, swap.swap, target.target, path.path, timer.timer, slice.slice, scope.scope
        ## FIXME(v4): same dead '$ck == $i' comparison as in the system-unit loop above.
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

if [[ $ok == true ]]
then
    ## WP-E.2.b: mutating a SYSTEM service via the generic `sc <service> <op>`
    ## shorthand is an operator/root action. service_action's own gate keys on
    ## plain uid 0, which ANY user reaches via `sudo srvctl.sh` (NOPASSWD
    ## sudoers) — so gate the shorthand HERE. Reads (status / no op) and --user
    ## services (the caller's own) stay open. Owner commands (update-ve,
    ## adjust-service) call service_action directly, gated by owner_only, so
    ## they are unaffected. NOTE (user review): this uses operators_only
    ## (root+operator) and REPLACES the old root/wheel gate — a wheel member who
    ## is not an operator no longer mutates arbitrary services via the shorthand;
    ## tighten to root_only if arbitrary host-service control should be root-only.
    if [[ -n "$op" ]] && [[ "$op" != status ]] && [[ -z "$xswitch" ]]
    then
        operators_only
    fi
    service_action "$service" "$op" "$xswitch"
    ## FIXME(v4): exit_0 runs unconditionally, so service_action failures
    ## (return 66 for non-root/non-wheel, 223 for unknown op, systemctl
    ## errors) all exit 0 — automation cannot detect a failed operation.
    exit_0
fi

## no unit matched: give control back to the dispatcher ("Invalid command.")
return 0

