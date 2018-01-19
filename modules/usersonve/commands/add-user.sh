#!/bin/bash

## @@@ add-user USERNAME
## @en Add user to the container
## &en Add user to the container, so that they have their own files, email accouns, and so on.
## &en users will have a default password, and a directory structure in the container home.

argument username

local username password home
username="${ARG,,}"

if ! [[ "$username" =~ ([a-z_][a-z0-9_]{2,30}) ]]
then
    err "Invalid username: $username"
    exit 22
fi

if id -u "$username" > /dev/null 2>&1
then
    err "User $username already exist."
else
    msg "Adding user $username"
    adduser "$username"
fi

home="$(getent passwd "$username" | cut -f6 -d:)"

if [[ -f $home/.password ]]
then
    msg "Reading password from .password file"
    password="$(cat "$home/.password")"
else
    msg "generating new password"
    password="$(new_password)"
fi

ntc "Password for $username is: $password"

echo "$password" | passwd "$username" --stdin 2> /dev/null 1> /dev/null
echo -e "$password" > "$home/.password"

echo "This is the mailing system at $HOSTNAME, your account has been created/updated." | mail -s "Welcome to $HOSTNAME" "$username@$HOSTNAME"

run chown -R "$username:$username" $home
