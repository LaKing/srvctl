#!/bin/bash

function regenerate_etc_hosts() {
    cfg system etc_hosts > /etc/hosts
}

function regenerate_etc_postfix_relaydomains() {
    if [[ -d /etc/postfix/ ]]
    then
        cfg system postfix_relaydomains > /etc/postfix/relaydomains
    fi
}

function regenerate_ssh_config() {
    mkdir -p /etc/ssh/ssh_config.d
    cfg system ssh_config > /etc/ssh/ssh_config.d/srvctl-containers.conf
    cfg system host_keys  > /etc/ssh/ssh_known_hosts
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
                    err "Container $C missing from database."
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