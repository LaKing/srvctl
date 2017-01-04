#!/bin/bash

# shellcheck disable=SC2154
[[ $SC_USE_datastore ]] || return

function regenerate_users() {
    
    msg "regenerate users"
    
    local userlist password passfile uid
    userlist="$(cfg system user_list)"
    
    for username in $userlist
    do
        if ! id -u "$username" > /dev/null 2>&1
        then
            uid=$(get user "$username" uid)
            run groupadd -g "$uid" "$username"
            run adduser  -u "$uid" -g "$uid" "$username"
        fi
        
        ## if not root, but an user existing on the system
        if [[ $username != root ]] && id -u "$username" > /dev/null 2>&1
        then
            ## update password?
            password="$(get user "$username" password)"
            passfile="$(getent passwd "$username" | cut -f6 -d:)/.password"
            if [[ ! -z "$password" ]]
            then
                if [[ ! -f $passfile ]] || [[ $password != "$(cat "$passfile")" ]]
                then
                    msg "Password-update for $username"
                    echo "$password" | passwd "$username" --stdin 2> /dev/null 1> /dev/null
                    echo -e "$password" > "$passfile"
                fi
            fi
        fi
    done
}
