#!/bin/bash

## @@@ delete-mail-queue-domain DOMAIN
## @en Delete the queued mail for DOMAIN from the host mail queue (irreversible)
## &en Only messages whose every recipient is in DOMAIN are deleted; the others are listed and kept.
## &en Check first with list-mail-queue DOMAIN.

root_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument domain
delete_mail_queue_domain "$ARG"
