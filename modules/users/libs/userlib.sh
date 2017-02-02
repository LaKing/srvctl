#!/bin/bash

# shellcheck disable=SC2154
[[ $SC_USE_datastore ]] || return

function regenerate_users() {
    
    msg "regenerate users"
    
    local userlist password passfile uid
    userlist="$(cfg system user_list)"
    
    for user in $userlist
    do
        if ! id -u "$user" > /dev/null 2>&1
        then
            uid="$(get user "$user" uid)"
            run groupadd -g "$uid" "$user"
            run adduser  -u "$uid" -g "$uid" "$user"
            exif
        fi
        
        ## if not root, but an user existing on the system
        if [[ $user != root ]] && id -u "$user" > /dev/null 2>&1
        then
            ## update password?
            password="$(get user "$user" password)"
            passfile="$(getent passwd "$user" | cut -f6 -d:)/.password"
            if [[ ! -z "$password" ]]
            then
                if [[ ! -f $passfile ]] || [[ $password != "$(cat "$passfile")" ]]
                then
                    msg "Password-update for $user"
                    echo "$password" | passwd "$user" --stdin 2> /dev/null 1> /dev/null
                    echo -e "$password" > "$passfile"
                fi
            fi
        fi
        
        create_user_ssh "$user"
        
        
        
    done
}

function create_user_ssh() { ## user
    
    local user home
    user="$1"
    home="$(getent passwd "$user" | cut -f6 -d:)"
    
    mkdir -p "$home/.ssh"
    
    ## create ssh keypair
    if [[ ! -f "$home/.ssh/id_rsa" ]] || [[ ! -f "$home/.ssh/id_rsa.pub" ]]
    then
        ssh-keygen -t rsa -b 4096 -f "$home/.ssh/id_rsa" -N '' -C "$user@$SC_COMPANY_DOMAIN ($HOSTNAME $NOW)"
    fi
    
    cat /root/.ssh/authorized_keys > "$home/.ssh/authorized_keys"
    cat "$home/.ssh/id_rsa.pub" >> "$home/.ssh/authorized_keys"
    
    
    
    ## TODO import publik keys
    
    chown -R "$user:$user" "$home/.ssh"
    chmod -R 600 "$home/.ssh"
    chmod    700 "$home/.ssh"
    
}
