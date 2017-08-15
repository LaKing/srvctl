#!/bin/bash

return

## this function has been implemented in node.js in the usersonhost module
## it is kept temporary for reference

function create_user_client_cert() { ## user
    local user home certfile
    user="$1"
    home="$(getent passwd "$user" | cut -f6 -d:)"
    certfile="$home/$user@$SC_COMPANY_DOMAIN.p12"
    
    msg "check & create_user_client_cert for $user"
    
    if [[ -f $certfile ]]
    then
        return
    fi
    
    if $SC_USE_CA
    then
        create_ca_certificate client usernet "$user"
    fi
    
    if [[ ! -f "$SC_DATASTORE_DIR/users/$user/$user@$SC_COMPANY_DOMAIN.p12" ]]
    then
        err "no client cert for $user"
        return
    fi
    
    if [[ ! -f "$home/$user@$SC_COMPANY_DOMAIN.p12" ]]
    then
        cat "$SC_DATASTORE_DIR/users/$user/$user@$SC_COMPANY_DOMAIN.p12" > "$home/$user@$SC_COMPANY_DOMAIN.p12"
        chown "$user:$user" "$home/$user@$SC_COMPANY_DOMAIN.p12"
        chmod 400 "$home/$user@$SC_COMPANY_DOMAIN.p12"
        
        cat "$SC_DATASTORE_DIR/users/$user/$user@$SC_COMPANY_DOMAIN.pass" > "$home/$user@$SC_COMPANY_DOMAIN.pass"
        chown "$user:$user" "$home/$user@$SC_COMPANY_DOMAIN.pass"
        chmod 400 "$home/$user@$SC_COMPANY_DOMAIN.pass"
        
        msg "Placed p12 client certificate in home folder for $user"
    fi
    
}
