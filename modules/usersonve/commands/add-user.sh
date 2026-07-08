#!/bin/bash

## @@@ add-user USERNAME
## @en Add user to the container
## &en Add user to the container, so that they have their own files, email accouns, and so on.
## &en users will have a default password, and a directory structure in the container home.

## Container-side add-or-update of a Linux user: creates the account if
## missing, (re)sets its password — reusing an existing $home/.password
## verbatim, else generating one via the password module — then rewrites
## $home/.password, mails a welcome notice and chowns the home directory.

## WP-E VE-side sweep: add the guards its siblings already carry. Managing
## container accounts + passwords is a container-admin (VE root) task. root_only
## (sc_is_root) is the REAL barrier: it denies a non-root VE user who reaches
## uid 0 via `sudo srvctl.sh`. ve_only marks it VE-scoped (see the ve_only note
## in srvctl authlib — context is enforced by the usersonve module condition).
ve_only
root_only

argument username

## local username password home
username="${ARG,,}"

## FIXME(v4): the regex is unanchored — any input containing one valid run
## passes (e.g. "bad!name", "-flag"), defeating validation; anchor with ^...$.
if ! [[ "$username" =~ ([a-z_][a-z0-9_]{0,30}) ]]
then
    err "Invalid username: $username"
    exit 22
fi

## Add-or-update contract: an existing user is reported but NOT an error —
## we fall through and reset its password below.
if id -u "$username" > /dev/null 2>&1
then
    err "User $username already exist."
else
    msg "Adding user $username"
    adduser "$username"
fi

## FIXME(v4): if adduser failed above, getent finds nothing and $home stays
## empty — the password file then lands at /.password and the success output
## below is misleading, since nothing was actually set.
home="$(getent passwd "$username" | cut -f6 -d:)"

## Reuse the persisted password so re-running keeps the credentials stable.
if [[ -f $home/.password ]]
then
    msg "Reading password from .password file"
    password="$(cat "$home/.password")"
else
    msg "generating new password"
    password="$(new_password)"
fi

ntc "Password for $username is: $password"

## FIXME(v4): passwd failures are invisible (stdout and stderr discarded);
## echo -e mangles passwords containing backslash sequences; and the
## plaintext .password file is created with root's umask (typically
## world-readable) before the recursive chown below. v4: use chpasswd,
## check the exit status, create the file with mode 0600.
echo "$password" | passwd "$username" --stdin 2> /dev/null 1> /dev/null
echo -e "$password" > "$home/.password"

## Local welcome mail to the new account on this container.
echo "This is the mailing system at $HOSTNAME, your account has been created/updated." | mail -s "Welcome to $HOSTNAME" "$username@$HOSTNAME"

run chown -R "$username:$username" "$home"
