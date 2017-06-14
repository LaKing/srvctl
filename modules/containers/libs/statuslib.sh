#!/bin/bash

function get_disk_usage {
    du -hs "/srv/$1" | head -c 4
}

function containerfarm_status() {
    
    local list
    if [[ $SC_USER == root ]]
    then
        list="$(cfg system container_list)" || exit 15
    else
        list="$(cfg user container_list)" || exit 15
    fi
    
    echo ''
    printf "${YELLOW}%-10s${CLEAR}" "STATUS"
    printf "${YELLOW}%-48s${CLEAR}" "HOSTNAME"
    printf "${YELLOW}%-14s${CLEAR}" "IP-INTERNAL"
    printf "${YELLOW}%-16s${CLEAR}" "RESELLER"
    printf "${YELLOW}%-16s${CLEAR}" "USERNAME"
    
    echo ''
    
    for C in $list
    do
        local ip ping_ms
        ip="$(get container "$C" ip)"
        exif "Could not get IP for $C"
        
        if ping_ms=$(ping -W 1 -c 1 "$ip" | grep rtt)
        then
            printf "${GREEN}%-10s${CLEAR}" "${ping_ms:23:5}ms"
        else
            printf "${RED}%-10s${CLEAR}" "ERROR"
        fi
        
        if [[ -d /srv/$C ]]
        then
            printf "${GREEN}%-48s${CLEAR}" "$C"
        else
            printf "${YELLOW}%-48s${CLEAR}" "$C"
        fi
        
        printf "${GREEN}%-14s${CLEAR}" "$ip"
        printf "${YELLOW}%-16s${CLEAR}" "$(get container "$C" reseller)"
        printf "${YELLOW}%-16s${CLEAR}" "$(get container "$C" user)"
        
        echo ''
    done
    
    echo ''
}

function check_hosts_connectivity() {
    ## simple rsync based data syncronization
    msg "Checking hosts connectivity ..."
    
    for host in $(cfg system host_list)
    do
        ntc "connecting ..."
        if [[ "$(ssh -n -o ConnectTimeout=1 "$host" hostname 2> /dev/null)" == "$host" ]]
        then
            msg "host $host is online"
            
        else
            err "host $host is offline"
        fi
    done
    
}

function check_containers_connectivity() {
    
    msg "Checking containers connectivity .."
    
    for container in $(cfg system container_list)
    do
        ntc "connecting to $container ..."
        if [[ "$(ssh -n -o ConnectTimeout=1 "$container" hostname 2> /dev/null)" == "$container" ]]
        then
            msg "container $container is online"
            
        else
            err "container $container is offline"
        fi
    done
}
