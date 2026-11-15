#!/bin/bash

## @@@ add-publickey KEY|FILE
## @en Add an ssh public key to your account
## &en Give the key itself (ssh-ed25519 AAAA... comment) or a file that holds it.
## &en The key opens your account on this host at once, your containers after the next regenerate.

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument key-or-file
users_only
sudomize

##
##   Stores an additional ssh public key of the caller as
##   $SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub. sshd reads that
##   directory on every login (modules/ssh/sshd_authorization.sh), and
##   regenerate copies the keys into the user's containers (ssh.js).
##
##   The command runs at uid 0 for every user, so nothing here opens a path
##   the caller names with root's rights: a FILE is read as the caller
##   (runuser), and there is no editor. A key in RFC4716 format gets one
##   conversion attempt; what ssh-keygen cannot read is not stored.
##

dir="$SC_DATASTORE_DIR/users/$SC_USER"
pub="$dir/$SC_USER-$NOW.pub"
tmp="$(mktemp)" || exit 1

if [[ -f $ARG ]]
then
    if sc_is_root
    then
        cat -- "$ARG" > "$tmp"
    else
        runuser -u "$SC_USER" -- cat -- "$ARG" > "$tmp"
    fi
else
    printf '%s\n' "$OPAS" > "$tmp"
fi

if ! ssh-keygen -l -f "$tmp" > /dev/null 2>&1
then
    ## not an OpenSSH key line: maybe the RFC4716 (PuTTY export) format
    if ssh-keygen -i -f "$tmp" > "$tmp.converted" 2> /dev/null && ssh-keygen -l -f "$tmp.converted" > /dev/null 2>&1
    then
        mv -f "$tmp.converted" "$tmp"
    else
        rm -f "$tmp" "$tmp.converted"
        err "This is not an ssh public key."
        exit 22
    fi
fi

mkdir -p "$dir"
mv -f "$tmp" "$pub"
chmod 644 "$pub"

msg "Added $pub"
ssh-keygen -l -f "$pub"
