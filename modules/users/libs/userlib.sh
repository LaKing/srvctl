#!/bin/bash

# shellcheck disable=SC2154
[[ $SC_USE_datastore ]] || return

function regenerate_users() {
    
    msg "regenerate users"
    
    local userlist password passfile uid
    userlist="$(cfg system user_list)"
    
    ## TODO maybe this should be javascript too
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
        
        ## function defined in modules/ssh/sshlib.sh
        create_user_ssh "$user"
        
        ## function defined in modules/certificates/certlib.sh
        create_user_client_cert "$user"
        
    done
}


