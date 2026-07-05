#!/bin/bash

##
##   modules/usersonhost/libs/userlib.sh — bash-side user provisioning.
##   Sourced into the srvctl shell by load_libs when the module is enabled.
##
##   Only regenerate_users is live, and it merely wraps userscfg (main.js);
##   it is called by commands/add-user.sh, commands/add-reseller.sh and by
##   modules/containers/commands/add-ve-user.sh. Everything else in this
##   file is an older bash implementation of the same reconciliation that
##   main.js performs; it sits behind an unconditional return and is
##   unreachable (kept for reference until the v4 cleanup).
##

## FIXME(v4): dead code — create_user_id is only referenced from the
## unreachable tail of regenerate_users below; it duplicates main.js
## logic and can silently drift from it.
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

## FIXME(v4): dead code — bash twin of the crate_user_password (sic) in
## main.js, only reachable via the dead create_user_id above; the "crate"
## typo is load-bearing in main.js too, rename both together in v4.
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

## Reconcile all cluster users on this host: delegates to main.js, which
## creates system accounts, passwords, ssh keys, client certificates and
## the per-container share mounts.
function regenerate_users() {

    msg "regenerate users"
    userscfg

    return

    ## FIXME(v4): dead code — everything below the return above is
    ## unreachable (the JS path in main.js replaced this loop); delete it
    ## together with create_user_id / crate_user_password in v4.
    local userlist password passfile passuser
    userlist="$(get cluster user_list)"

    ## optimized for speed, we just check if the user already exists, and perform all the action if not.
    for user in $userlist
    do
        if [[ $user != root ]]
        then
            create_user_id "$user"
        fi
    done
}
