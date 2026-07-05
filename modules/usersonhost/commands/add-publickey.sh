#!/bin/bash

## @@@ add-publickey [KEY|FILE]
## @en Add an ssh publickey to the current cluster
## &en Create the file as user defined publickey in the current cluster datastore and save it on the system.
## &en Without argiument, the command will open the mcedit program, so the key can be pasted inside.

sudomize

##
##   Stores an additional ssh public key for the calling user in the
##   cluster datastore, as users/$SC_USER/$SC_USER-$NOW.pub (the $NOW
##   timestamp contains colons). Input can be a file path, the key text
##   itself passed as arguments, or — with no argument — an interactive
##   mcedit session. The result is verified with ssh-keygen; a key in
##   RFC4716 format gets one conversion attempt, and an unverifiable
##   file is removed again.
##

## FIXME(v4): no readonly-datastore guard — an SC_DATASTORE_RO check was
## sketched here but never enabled; on a readonly datastore the writes
## below fail with raw shell errors.

msg "Adding $SC_USER-$NOW.pub"

pub="$SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub"

## FIXME(v4): the second test is redundant — with an empty ARG, -f "" is
## already false, so the condition is just "no argument given"
if [[ -z $ARG ]] && [[ ! -f $ARG ]]
then
    ## interactive path; return works because commands are sourced
    ## inside run_command
    mcedit "$pub"
    msg "edited file $pub"
    return
else
    if [[ ! -f $ARG ]]
    then
        ## not a file: treat all command arguments as the key text
        echo "$OPAS" >> "$pub"
    else
        cat "$ARG" >> "$pub"
    fi
fi

if [[ -z "$(cat "$pub")" ]]
then
    rm -fr "$pub"
fi

## FIXME(v4): on the empty-input path the file was just removed, so this
## cat prints a stray "No such file" error and the verification cascade
## below runs against a missing file.
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
    ## bugfix(v4-polish): was 'run ssh-keygen -i ... > "$pub"' — run echoes
    ## its command banner to stdout, so the banner landed inside the key
    ## file and the conversion result could never verify
    if ssh-keygen -i -f "$pub.tmp" > "$pub"
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
