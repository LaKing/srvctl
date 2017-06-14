#!/bin/bash

function regenerate_ssh_config() {
    msg "regenerate ssh configs"
    
    rm -fr /var/srvctl3/share/containers/*/users/*/authorized_keys
    
    ssh_main
    
    # moved to js
    #check_hosts_ssh_keys
    #check_containers_ssh_keys
}

function update_install_ssh_config() {
    
    if [[ ! $SC_HOSTNET ]]
    then
        return
    fi
    
    msg "Update-install ssh configurations."
    
    ## host keys first
    #echo '' > /etc/ssh/ssh_known_hosts
    
    ## we could store host_keys in our datastore (as well). But we wont. At least not for now.
    #cfg system host_keys
    
    echo "## Scan $NOW" > /etc/ssh/ssh_known_hosts
    check_hosts_ssh_keys
    #check_containers_ssh_keys
    
    mkdir -p /etc/ssh/ssh_config.d
    ssh_main
    
    ## authorized keys
    ## we will store keys in the datastore dir and in /etc/srvctl
    ## for that we will use multiple AuthorizedKeysFile entries.
    
    cat "$SC_INSTALL_DIR/modules/ssh/sshd_config" > /etc/ssh/sshd_config
    
    if [[ ! -f /etc/srvctl/authorized_keys ]] && [[ -f /etc/srvctl/data/authorized_keys ]]
    then
        msg "Import root authorized_keys from etc/srvctl/data dir"
        cat /etc/srvctl/data/authorized_keys > /etc/srvctl/authorized_keys
    fi
    
    if [[ ! -f /etc/srvctl/authorized_keys ]] && [[ -f /root/.ssh/authorized_keys ]]
    then
        msg "Import root authorized_keys from /root/.ssh dir"
        cat /root/.ssh/authorized_keys > /etc/srvctl/authorized_keys
    fi
    
    chown root:root /etc/srvctl/authorized_keys
    chmod 600 /etc/srvctl/authorized_keys
    
    mkdir -p "$SC_DATASTORE_RW_DIR/users"
    
    run systemctl enable sshd
    run systemctl restart sshd
    run systemctl status sshd --no-pager
    
    mkdir -p /var/srvctl3/ssh
    echo '' > /var/srvctl3/ssh/known_hosts
}

function check_host_ssh_keys() { ## host
    local host ip tempfile tempstr dest
    
    host="$1"
    
    if ! grep -q "## $host by hostname" /var/srvctl3/ssh/known_hosts
    then
        tempfile=$(mktemp)
        
        ssh-keyscan -t rsa "$host" > "$tempfile" || continue
        
        tempstr="$(cat "$tempfile")"
        
        if [[ ! -z "$tempstr" ]]
        then
            
            ntc "Adding host-key by hostname"
            {
                echo ""
                echo "## $host by hostname $NOW"
                echo "$tempstr"
            } >> /var/srvctl3/ssh/known_hosts
            
        else
            err "Could not add host key for hostname $host"
        fi
    fi
    
    if [[ $host == localhost ]]
    then
        ip="127.0.0.1"
    else
        ip="$(get host "$host" host_ip)"
    fi
    
    
    if [[ ! -z "$ip" ]]
    then
        if ! grep -q "## $host by ip" /var/srvctl3/ssh/known_hosts
        then
            tempfile=$(mktemp)
            
            ssh-keyscan -t rsa "$ip" > "$tempfile" || continue
            tempstr="$(cat "$tempfile")"
            
            if [[ ! -z "$tempstr" ]]
            then
                ntc "Adding host-key by ip"
                {
                    echo ""
                    echo "## $host by ip $NOW"
                    echo "$tempstr"
                } >> /var/srvctl3/ssh/known_hosts
            else
                err "Could not add host key by ip $ip for hostname $host"
            fi
        fi
    fi
}

function check_hosts_ssh_keys() {
    ## simple rsync based data syncronization
    msg "Checking ssh connectivity and server host-keys"
    local hostlist
    hostlist="localhost $(cfg system host_list)"
    
    #msg "hosts: $hostlist"
    tempfile=$(mktemp)
    
    if [[ ! -f /var/srvctl3/ssh/known_hosts ]]
    then
        mkdir -p /var/srvctl3/ssh
        echo '' > /var/srvctl3/ssh/known_hosts
    fi
    
    for host in $hostlist
    do
        check_host_ssh_keys $host
    done
    
}

function check_container_ssh_keys() { ## container
    
    
    local container ip tempfile tempstr dest
    container="$1"
    
    if ! grep -q "## $container by hostname" /var/srvctl3/ssh/known_hosts
    then
        tempfile=$(mktemp)
        ssh-keyscan -t rsa "$container" > "$tempfile" || continue
        tempstr="$(cat "$tempfile")"
        
        if [[ ! -z "$tempstr" ]]
        then
            ntc "Adding host-key by hostname $container"
            {
                echo ""
                echo "## $container by hostname $NOW"
                echo "$tempstr"
            } >> /var/srvctl3/ssh/known_hosts
        else
            err "Could not add host key for container $container"
        fi
    fi
    
    ip="$(get container "$container" ip)"
    
    if [[ ! -z "$ip" ]]
    then
        if ! grep -q "## $container by ip" /var/srvctl3/ssh/known_hosts
        then
            tempfile=$(mktemp)
            ssh-keyscan -t rsa "$ip" > "$tempfile" || continue
            tempstr="$(cat "$tempfile")"
            
            if [[ ! -z "$tempstr" ]]
            then
                ntc "Adding $container host-key by ip $ip"
                {
                    echo ""
                    echo "## $container by ip $NOW"
                    echo "$tempstr"
                } >> /var/srvctl3/ssh/known_hosts
            else
                err "Could not add container key by ip $ip for hostname $container"
            fi
        fi
    fi
}


function check_containers_ssh_keys() {
    
    #### Actually we do not check for host keys when connecting to internal containers.
    msg "Checking ssh connectivity and container host-keys"
    local hostlist ip tempfile tempstr dest
    containerlist="$(cfg system container_list)"
    dest=/var/srvctl3/ssh/known_hosts
    
    #msg "containers: $containerlist"
    
    if [[ ! -f /var/srvctl3/ssh/known_hosts ]]
    then
        mkdir -p /var/srvctl3/ssh
        echo '' > /var/srvctl3/ssh/known_hosts
    fi
    
    for container in $containerlist
    do
        check_container_ssh_keys "$container"
    done
}


