#!/bin/bash

function regenerate_etc_hosts() {
    cfg system etc_hosts
    #> /etc/hosts
}

function regenerate_etc_postfix_relaydomains() {
    if [[ -d /etc/postfix/ ]]
    then
        cfg system postfix_relaydomains
    fi
}

function regenerate_ssh_config() {
    
    #echo '' > /etc/ssh/ssh_known_hosts
    
    ## we could store host_keys in our datastore (as well). But we wont. At least not for now.
    #cfg system host_keys
    
    check_hosts_connectivity
    
    mkdir -p /etc/ssh/ssh_config.d
    cfg system ssh_config
}

function check_hosts_connectivity() {
    ## simple rsync based data syncronization
    msg "Checking ssh connectivity and host-keys"
    local hostlist ip tempfile tempstr dest
    hostlist="$(cfg system host_list)"
    containerlist="$(cfg system container_list)"
    dest=/etc/ssh/ssh_known_hosts
    echo "## Scan $NOW" > "$dest"
    
    msg "hosts: $hostlist"
    
    for host in $hostlist
    do
        ip="$(get host "$host" host_ip)"
        
        ntc "$host: $ip"
        tempfile=$(mktemp)
        
        if ! grep "## $host by hostname" "$dest"
        then
            ssh-keyscan -t rsa "$host" > "$tempfile" || continue
            
            tempstr="$(cat "$tempfile")"
            
            if [[ ! -z "$tempstr" ]]
            then
                ntc "Adding host-key by hostname"
                echo "" >> "$dest"
                ## add a comment
                echo "## $host by hostname $NOW" >> "$dest"
                ## and the key
                echo $tempstr >> "$dest"
                ## add to datastore
                #
            else
                err "Could not add host key for hostname $host"
            fi
        fi
        
        if [[ ! -z "$ip" ]]
        then
            if ! grep "## $host by ip" "$dest"
            then
                ssh-keyscan -t rsa "$ip" > $tempfile || continue
                tempstr="$(cat $tempfile)"
                
                if [[ ! -z "$tempstr" ]]
                then
                    ntc "Adding host-key by ip"
                    echo "" >> "$dest"
                    echo "## $host by ip $NOW" >> "$dest"
                    echo $tempstr >> "$dest"
                    ## add to datastore
                    #
                else
                    err "Could not add host key by ip $ip for hostname $host"
                fi
            fi
        fi
        
        ntc "connecting ..."
        if [[ "$(ssh -n -o ConnectTimeout=1 "$host" hostname 2> /dev/null)" == "$host" ]]
        then
            msg "host $host is online"
            
        else
            err "host $host is offline"
        fi
    done
    
    msg "containers: $containerlist"
    
    for container in $containerlist
    do
        ip="$(get container "$container" ip)"
        
        ntc "$container: $ip"
        tempfile=$(mktemp)
        
        if ! grep "## $container by hostname" "$dest"
        then
            ssh-keyscan -t rsa "$container" > "$tempfile" || continue
            
            tempstr="$(cat "$tempfile")"
            
            if [[ ! -z "$tempstr" ]]
            then
                ntc "Adding host-key by hostname"
                echo "" >> "$dest"
                ## add a comment
                echo "## $container by hostname $NOW" >> "$dest"
                ## and the key
                echo $tempstr >> "$dest"
                ## add to datastore
                #
            else
                err "Could not add host key for container $container"
            fi
        fi
        
        if [[ ! -z "$ip" ]]
        then
            if ! grep "## $container by ip" "$dest"
            then
                ssh-keyscan -t rsa "$ip" > $tempfile || continue
                tempstr="$(cat $tempfile)"
                
                if [[ ! -z "$tempstr" ]]
                then
                    ntc "Adding host-key by ip"
                    echo "" >> "$dest"
                    echo "## $container by ip $NOW" >> "$dest"
                    echo $tempstr >> "$dest"
                    ## add to datastore
                    #
                else
                    err "Could not add container key by ip $ip for hostname $container"
                fi
            fi
        fi
        
        ntc "connecting ..."
        if [[ "$(ssh -n -o ConnectTimeout=1 "$container" hostname 2> /dev/null)" == "$container" ]]
        then
            msg "container $container is online"
            
        else
            err "container $container is offline"
        fi
    done
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
