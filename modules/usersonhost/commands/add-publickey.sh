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


if [[ -z $ARG ]] && [[ ! -f $ARG ]]
then
    mcedit "$SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub"
    msg "edited file $SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub"
    return
else
    if [[ ! -f $ARG ]]
    then
        echo "$ARG" >> "$SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub"
    else
        cat "$ARG" >> "$SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub"
    fi
fi

if [[ -z "$(cat "$SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub")" ]]
then
    rm -fr "$SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub"
fi

msg "OK"
