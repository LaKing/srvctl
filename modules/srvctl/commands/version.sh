#!/bin/bash

## @@@ version
## @en List software versions installed.
## &en Contact the package manager, and query important packages
## &en

## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

## Place your code here ...

msg "-- software-versions --"

msg_version_installed postfix
msg_version_installed nodejs

if $ON_HS
then
    msg_version_installed Pound
    #pound -V 2> /dev/null | grep Version
    msg_version_installed perdition
    msg_version_installed fail2ban
    msg_version_installed bind
    msg_version_installed clamav
fi
