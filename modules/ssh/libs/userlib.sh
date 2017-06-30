#!/bin/bash

function create_user_ssh() { ## user
    
    local user home
    user="$1"
    home="$(getent passwd "$user" | cut -f6 -d:)"
    
    msg "create_user_ssh for $user"
    
    [[ $user == root ]] && return;
    
    ## create ssh keypair
    if [[ ! -f "$SC_DATASTORE_DIR/users/$user/id_rsa" ]] || [[ ! -f "$SC_DATASTORE_DIR/users/$user/srvctl_id_rsa" ]] || [[ ! -f "$home/.ssh/id_rsa" ]]
    then
        msg "Update on ssh configuration for $user"
        
        mkdir -p "$SC_DATASTORE_DIR/users/$user"
        chmod 600 "$SC_DATASTORE_DIR/users/$user"
        
        ## the id_rsa (without prefix) will be placed in the users home directory.
        ## that means users have access to the keyfile.
        
        if [[ ! -f "$SC_DATASTORE_DIR/users/$user/id_rsa" ]]
        then
            msg "Create datastore user id_rsa for $user"
            ssh-keygen -t rsa -b 4096 -f "$SC_DATASTORE_DIR/users/$user/id_rsa" -N '' -C "$user@$SC_COMPANY_DOMAIN (id_rsa $HOSTNAME $NOW)"
            exif
        fi
        
        ## the srvctl_id_rsa is used internally, in the srvctl-gui, in sshpiperd, and in the reseller-user structure.
        ## that means users do not have access to the keyfile, thus we can say they are save and wont be compromised.
        
        if [[ ! -f "$SC_DATASTORE_DIR/users/$user/srvctl_id_rsa" ]]
        then
            msg "Create datastore srvctl id_rsa for $user"
            ssh-keygen -t rsa -b 4096 -f "$SC_DATASTORE_DIR/users/$user/srvctl_id_rsa" -N '' -C "$user@$SC_COMPANY_DOMAIN (srvctl $HOSTNAME-$NOW)"
            exif
        fi
        
        mkdir -p "$home/.ssh"
        cat "$SC_DATASTORE_DIR/users/$user/id_rsa.pub" > "$home/.ssh/id_rsa.pub"
        cat "$SC_DATASTORE_DIR/users/$user/id_rsa" > "$home/.ssh/id_rsa"
        
        chown -R "$user:$user" "$home/.ssh"
        chmod -R 600 "$home/.ssh"
        chmod    700 "$home/.ssh"
    fi
    
    reseller="$(get user "$user" reseller)"
    if [[ "$reseller" != "$user" ]] && [[ "$reseller" != root ]]
    then
        [[ -f "$SC_DATASTORE_DIR/users/$user/reseller_id_rsa.pub" ]] || ln -s "../$reseller/id_rsa.pub" "$SC_DATASTORE_DIR/users/$user/reseller_id_rsa.pub"
        [[ -f "$SC_DATASTORE_DIR/users/$user/reseller_srvctl_id_rsa.pub" ]] || ln -s "../$reseller/srvctl_id_rsa.pub" "$SC_DATASTORE_DIR/users/$user/reseller_srvctl_id_rsa.pub"
    fi
    
    ## TODO import user added public keys
}
