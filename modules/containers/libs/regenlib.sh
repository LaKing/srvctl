#!/bin/bash

function regenerate_all_hosts() {
    msg "Regenerate hosts in cluster $SC_CLUSTERNAME"
    for host in $(get cluster host_list)
    do
        msg "regenerate $host"
        if [[ $host == "$HOSTNAME" ]]
        then
            run_hook regenerate
        else
            if ! run ssh -o ConnectTimeout=1 -o BatchMode=yes "$host" "srvctl regenerate" 2> /dev/null
            then
                err "Skipping unreachable host $host"
            fi
        fi
        
    done
    
}

function regenerate_etc_hosts() {
    msg "regenerate /etc/hosts"
    get cluster etc_hosts > /etc/hosts
}


function check_container_directories() {
    msg "Checking for containers in directories"
    for D in /srv/*
    do
        if [[ $D == /srv/TEMP ]]
        then
            continue
        fi
        
        if [[ -d $D/rootfs ]]
        then
            local C
            
            ## strip /srv
            C="${D:5}"
            
            
            if [[ "$(get container "$C" exist)" != true ]]
            then
                if [[ -f $D/rootfs/etc/os-release ]]
                then
                    err "Container $C missing from database!"
                    ## AUTOFIX
                    ## C appears to have a valid filesystem
                    local T
                    if [[ -f /srv/$C/ctype ]]
                    then
                        T="$(cat "/srv/$C/ctype")"
                    else
                        # shellcheck disable=SC1090
                        T="$(source "$D/rootfs/etc/os-release" && echo "$ID")"
                    fi
                    
                    
                    new container "$C" "$T"
                    msg "Imported $T $C to database."
                    if [[ -f /srv/$C/ipv4-address ]] && [[ -f /srv/$C/bridge-address ]]
                    then
                        put container "$C" ip "$(cat "/srv/$C/ipv4-address")"
                        put container "$C" br "$(cat "/srv/$C/bridge-address")"
                    else
                        create_nspawn_container_config "$C"
                    fi
                fi
            fi
            
            if [[ -d /srv/$C/rootfs/etc ]]
            then
                if [[ ! -e "/etc/systemd/system/machines.target.wants/srvctl-nspawn@$C.service" ]]
                then
                    run systemctl enable "srvctl-nspawn@$C"
                fi
                
                if [[ ! -f /srv/$C/hosts ]] || [[ ! -f /srv/$C/$C.nspawn ]]
                then
                    msg "Updating container configuration for $C"
                    
                    #cfg container "$C" update_ip
                    create_nspawn_container_config "$C"
                fi
            fi
            
            #if [[ ! -f /srv/$C/cert/$C.crt ]] || [[ ! -f /srv/$C/cert/$C.key ]] || [[ ! -f /srv/$C/cert/$C.pem ]]
            #then
            #    msg "No certificate for $C - fix: srvctl-exec-function add_ve_certificate $C"
            #fi
        fi
    done
}

function check_container_database() {
    msg "Checking for containers in the database"
    local container_list h
    container_list="$(get cluster container_list)"
    for C in $container_list
    do
        h="$(get container "$C" host)"
        if [[ "$h" == "$HOSTNAME" ]]
        then
            ## this container should be on that host
            if ! [[ -d /srv/$C ]]
            then
                msg "Create local container"
                local T
                T="$(get container "$C" type)"
                create_nspawn_container_filesystem "$C"
                create_nspawn_container_config "$C"
            fi
        fi
    done
}

function check_container_ownership() {
    msg "Checking for container owners in the database"
    local container_list
    container_list="$(get cluster container_list)"
    for C in $container_list
    do
        if [[ $(get container "$C" user_ip_match) ]]
        then
            continue
        else
            msg "Re-setting internal IP of $C due to false user_ip_match"
            
            run systemctl stop srvctl-nspawn@"$C"
            cfg container "$C" update_ip
            
            create_nspawn_container_config "$C"
            
            run systemctl start srvctl-nspawn@"$C" --no-pager -n 30
            run systemctl status srvctl-nspawn@"$C" --no-pager -n 30
        fi
    done
}

