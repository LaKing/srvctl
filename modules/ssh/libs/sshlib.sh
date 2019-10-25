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
    # get cluster host_keys > /etc/ssh/ssh_known_hosts
    
    mkdir -p /etc/ssh/ssh_config.d
    mkdir -p /var/srvctl3/share/common
    mkdir -p /var/srvctl3/ssh
    ssh_main
    
    ## authorized keys
    ## we will store keys in the datastore dir and in /etc/srvctl
    ## for that we will use multiple AuthorizedKeysFile entries.
    
    cat "$SC_INSTALL_DIR/modules/ssh/sshd_config" > /etc/ssh/sshd_config
    
    if [[ ! -f /var/srvctl3/share/common/authorized_keys ]] && [[ -f /etc/srvctl/data/authorized_keys ]]
    then
        msg "Import root authorized_keys from /etc/srvctl/data dir"
        cat /etc/srvctl/data/authorized_keys > /var/srvctl3/share/common/authorized_keys
    fi
    
    if [[ ! -f /var/srvctl3/share/common/authorized_keys ]] && [[ -f /root/.ssh/authorized_keys ]]
    then
        msg "Import root authorized_keys from /root/.ssh dir"
        cat /root/.ssh/authorized_keys > /var/srvctl3/share/common/authorized_keys
    fi
    
    chown root:root /var/srvctl3/share/common/authorized_keys
    chmod 644 /var/srvctl3/share/common/authorized_keys
    
    ## users need to access this file
    chmod -R 644 /var/srvctl3/ssh/known_hosts
    chmod +X /var/srvctl3/ssh
    
    mkdir -p "$SC_DATASTORE_RW_DIR/users"
    
    run systemctl enable sshd
    run systemctl restart sshd
    run systemctl status sshd --no-pager
    
}

function update_container_sshd_config() { ## rootfs
    cat "$SC_INSTALL_DIR/modules/ssh/sshd_config" > "$1"/etc/ssh/sshd_config
}

