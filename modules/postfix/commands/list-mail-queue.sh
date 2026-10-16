#!/bin/bash

## @@@ list-mail-queue [DOMAIN]
## @en List the host mail queue, or only the mail for DOMAIN: id, arrival, sender, recipients, subject
## &en Arrival time is UTC. A message is shown when any recipient is in DOMAIN.
## &en Look at one with show-mail-queue-message ID, drop a domain's with delete-mail-queue-domain DOMAIN.

root_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

list_mail_queue "$ARG"
