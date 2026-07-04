#!/bin/bash

## @@@ testsaslauthd user@ve
## @en test a given user of a container for email-functionality
## &en This command runs the testsaslauthd command, with the password automatically filled in..


## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

root_only
hs_only

sudomize

user="$(echo "$ARG" | cut -d'@' -f1)"
domain="$(echo "$ARG" | cut -d'@' -f2)"

if [ -f /srv/$domain/rootfs/home/$user/.password ]
then
    msg "Container $domain"
    password="$(cat /srv/$domain/rootfs/home/$user/.password)"
fi

if [ -f /srv/mail.$domain/rootfs/home/$user/.password ]
then
    msg "Container mail.$domain"
    password="$(cat /srv/mail.$domain/rootfs/home/$user/.password)"
fi

if [[ ! $password ]]
then
    echo "Mission failed."
fi

run testsaslauthd -u "$ARG" -p "$password"