#!/bin/bash

function create_user_id() { ## user
    local user
    user="$1"
    if ! id -u "$user" > /dev/null 2>&1
    then
        run adduser "$user"
        exif "adduser failed for $user"
        id "$user"
        
        ## store some sensitive data here
        mkdir -p "$SC_DATASTORE_DIR/users/$user"
        
        crate_user_password "$user"
        
        ## function defined in modules/ssh/userlib.sh
        create_user_ssh "$user"
        
        ## function defined in modules/certificates/certlib.sh
        create_user_client_cert "$user"
    fi
}

function crate_user_password() { ## user
    local user password passfile passuser
    user="$1"
    msg "create user password"
    ## if not root, but an user existing on the system
    
    if [[ $user != root ]] && id -u "$user" > /dev/null 2>&1
    then
        ## update password?
        
        passfile="$SC_DATASTORE_DIR/users/$user/.password"
        passuser="$(getent passwd "$user" | cut -f6 -d:)/.password"
        
        if [[ -f $passfile ]]
        then
            password="$(cat "$passfile")"
        fi
        
        if [[ -z $password ]]
        then
            password="$(new_password)"
            echo "$password" > "$passfile"
        fi
        
        #msg "Password-update for $user $password"
        echo "$password" | passwd "$user" --stdin 2> /dev/null 1> /dev/null
        echo "$password" > "$passuser"
    fi
}

function regenerate_users() {
    
    msg "regenerate users"
    
    local userlist password passfile passuser
    userlist="$(cfg system user_list)"
    
    ## optimized for speed, we just check if the user already exists, and perform all the action if not.
    for user in $userlist
    do
        if [[ $user != root ]]
        then
            create_user_id "$user"
        fi
    done
}


