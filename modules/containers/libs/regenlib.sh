#!/bin/bash

function regenerate_all_hosts() {
    
    for host in $(cfg system host_list)
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
    cfg system etc_hosts
    #> /etc/hosts
}


function check_container_directories() {
    msg "Checking for containers in directories"
    for D in /srv/*
    do
        if [[ -d $D ]]
        then
            local C
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
                        T="$(source "$D/rootfs/etc/os-release" && echo "$ID")"
                    fi
                    
                    
                    new container "$C" "$T"
                    msg "Imported $T $C to database."
                    if [[ -f /srv/$C/ipv4-address ]] && [[ -f /srv/$C/bridge-address ]]
                    then
                        put container "$C" ip "$(cat "/srv/$C/ipv4-address")"
                        put container "$C" br "$(cat "/srv/$C/bridge-address")"
                    else
                        create_nspawn_container_network "$C" "$T"
                    fi
                fi
            fi
        fi
    done
}

function check_container_database() {
    msg "Checking for containers in the database"
    local container_list h
    container_list="$(cfg system container_list)"
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
                create_nspawn_container_filesystem "$C" "$T"
                create_nspawn_container_network "$C" "$T"
            fi
        fi
    done
}
