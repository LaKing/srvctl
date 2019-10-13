#!/bin/bash

## @@@ add-publickey [KEY|FILE]
## @en Add an ssh publickey to the current cluster
## &en Create the file as user defined publickey in the current cluster datastore and save it on the system.
## &en Without argiument, the command will open the mcedit program, so the key can be pasted inside.

sudomize

## check if datastore is RW?
#if $SC_DATASTORE_RO
#then
#    err "Datastore is readonly."
#    exit
#fi

msg "Adding $SC_USER-$NOW.pub"

pub="$SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub"

if [[ -z $ARG ]] && [[ ! -f $ARG ]]
then
    mcedit "$pub"
    msg "edited file $pub"
    return
else
    if [[ ! -f $ARG ]]
    then
        echo "$OPAS" >> "$pub"
    else
        cat "$ARG" >> "$pub"
    fi
fi

if [[ -z "$(cat "$pub")" ]]
then
    rm -fr "$pub"
fi

cat "$pub"
echo ''

msg "Verifying ..."
if run ssh-keygen -l -f "$pub"
then
    msg "OK"
else
    err "Failed."
    msg "Trying to convert to the openssh format..."
    cat "$pub" > "$pub.tmp"
    if run ssh-keygen -i -f "$pub.tmp" > "$pub"
    then
        msg "Success!"
    else
        err "Failed to convert."
    fi
    run rm -fr "$pub.tmp"
    
    msg "Verifying ..."
    if run ssh-keygen -l -f "$pub"
    then
        msg "OK"
    else
        err "Could not verify the publikkey, removing."
        run rm -fr "$pub"
    fi
fi