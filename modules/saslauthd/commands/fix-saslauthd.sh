#!/bin/bash

## @@@ fix-saslauthd
## @en restart saslauthd
## &en This command restarts saslauthd to fix mailing.
## &en It is temporary..

## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

## Place your code here ...

sudomize

if systemctl restart saslauthd
then
    systemctl status saslauthd --no-pager
    msg "Successfully restarted saslauthd"
else
    err "Saslauthd Restart FAILED"
fi
