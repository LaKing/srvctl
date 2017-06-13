#!/bin/bash

function regenerate_ssh_config() {
    msg "regenerate ssh configs"
    
    rm -fr /var/srvctl3/share/containers/*/users/*/authorized_keys
    
    ssh_main
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
}

function check_hosts_ssh_keys() {
    ## simple rsync based data syncronization
    msg "Checking ssh connectivity and server host-keys"
    local hostlist ip tempfile tempstr dest
    hostlist="$(cfg system host_list)"
    
    dest=/etc/ssh/ssh_known_hosts
    
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
                # shellcheck disable=SC2129
                echo "" >> "$dest"
                ## add a comment
                echo "## $host by hostname $NOW" >> "$dest"
                ## and the key
                echo "$tempstr" >> "$dest"
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
                ssh-keyscan -t rsa "$ip" > "$tempfile" || continue
                tempstr="$(cat "$tempfile")"
                
                if [[ ! -z "$tempstr" ]]
                then
                    ntc "Adding host-key by ip"
                    # shellcheck disable=SC2129
                    echo "" >> "$dest"
                    ## add a comment
                    echo "## $host by ip $NOW" >> "$dest"
                    ## add the key
                    echo "$tempstr" >> "$dest"
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
    
}

## this function is deprecated actually.
function check_containers_ssh_keys() {
    
    #### Actually we do not check for host keys when connecting to internal containers.
    msg "Checking ssh connectivity and container host-keys"
    local hostlist ip tempfile tempstr dest
    containerlist="$(cfg system container_list)"
    dest=/etc/ssh/ssh_known_hosts
    
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
                # shellcheck disable=SC2129
                echo "" >> "$dest"
                ## add a comment
                echo "## $container by hostname $NOW" >> "$dest"
                ## and the key
                echo "$tempstr" >> "$dest"
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
                ssh-keyscan -t rsa "$ip" > "$tempfile" || continue
                tempstr="$(cat "$tempfile")"
                
                if [[ ! -z "$tempstr" ]]
                then
                    ntc "Adding host-key by ip"
                    # shellcheck disable=SC2129
                    echo "" >> "$dest"
                    ## add a comment
                    echo "## $container by ip $NOW" >> "$dest"
                    ## add the key
                    echo "$tempstr" >> "$dest"
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


