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
    
    mkdir -p /var/srvctl3/ssh
    echo '' > /var/srvctl3/ssh/known_hosts
}

