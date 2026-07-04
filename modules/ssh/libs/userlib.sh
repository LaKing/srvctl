#!/bin/bash
return

## this function has been replaced with a nodejs implementation in the usersonhost module.
## It is kept here temporary as a reference.

function create_user_ssh() { ## user ## reseller
    
    local user home reseller
    user="$1"
    reseller="$1"
    home="$(getent passwd "$user" | cut -f6 -d:)"
    
    msg "create_user_ssh for $user"
    
    if [[ $user == root ]]
    then
        return;
    else
        msg "Update on ssh configuration for $user"
        
        mkdir -p "$SC_DATASTORE_DIR/users/$user"
        chmod 600 "$SC_DATASTORE_DIR/users/$user"
        
        ## the id_ecdsa (without prefix) will be placed in the users home directory.
        ## that means users have access to the keyfile.
        
        if [[ ! -f "$SC_DATASTORE_DIR/users/$user/id_ecdsa" ]]
        then
            msg "Create datastore user id_ecdsa for $user"
            ssh-keygen -t ecdsa -f "$SC_DATASTORE_DIR/users/$user/id_ecdsa" -N '' -C "$user@$SC_COMPANY_DOMAIN (id_ecdsa $HOSTNAME $NOW)"
            exif
        fi
        
        ## the srvctl_id_ecdsa is used internally, in the srvctl-gui, in sshpiperd, and in the reseller-user structure.
        ## that means users do not have access to the keyfile, thus we can say they are save and wont be compromised.
        
        if [[ ! -f "$SC_DATASTORE_DIR/users/$user/srvctl_id_ecdsa" ]]
        then
            msg "Create datastore srvctl id_ecdsa for $user"
            ssh-keygen -t ecdsa -f "$SC_DATASTORE_DIR/users/$user/srvctl_id_ecdsa" -N '' -C "$user@$SC_COMPANY_DOMAIN (srvctl $HOSTNAME-$NOW)"
            exif
        fi
        
        if [[ ! -f "$home/.ssh/id_ecdsa" ]]
        then
            mkdir -p "$home/.ssh"
            cat "$SC_DATASTORE_DIR/users/$user/id_ecdsa.pub" > "$home/.ssh/id_ecdsa.pub"
            cat "$SC_DATASTORE_DIR/users/$user/id_ecdsa" > "$home/.ssh/id_ecdsa"
        fi
        
        chown -R "$user:$user" "$home/.ssh"
        chmod -R 600 "$home/.ssh"
        chmod    700 "$home/.ssh"
    fi
    
    
    if [[ -n "$reseller" ]] && [[ "$reseller" != "$user" ]] && [[ "$reseller" != root ]]
    then
        [[ -f "$SC_DATASTORE_DIR/users/$user/reseller_id_ecdsa.pub" ]] || ln -s "../$reseller/id_ecdsa.pub" "$SC_DATASTORE_DIR/users/$user/reseller_id_ecdsa.pub"
        [[ -f "$SC_DATASTORE_DIR/users/$user/reseller_srvctl_id_ecdsa.pub" ]] || ln -s "../$reseller/srvctl_id_ecdsa.pub" "$SC_DATASTORE_DIR/users/$user/reseller_srvctl_id_ecdsa.pub"
    fi
    
    ## TODO import user added public keys
}
