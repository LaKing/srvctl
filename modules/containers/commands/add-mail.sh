#!/bin/bash

## @@@ add-mail NAME
## @en Add a mailing container.
## &en Mail container for pop3/imap6smtp access.
## &en Contains dovecot, postfix.

argument container-name
authorize
sudomize



if [[ "${ARG:0:5}" == "mail." ]]
then
    C="$ARG"
else
    C="mail.$ARG"
fi

add_ve mail "$C"

run_hook add-ve
run_hook regenerate

