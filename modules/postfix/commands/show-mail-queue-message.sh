#!/bin/bash

## @@@ show-mail-queue-message ID
## @en Show one message of the host mail queue, headers and body, by its queue ID
## &en The ID comes from list-mail-queue. The mail is untrusted content: do not open its links.

root_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument queue-id
[[ $ARG =~ ^[0-9A-Za-z]+$ ]] || { err "Invalid queue ID: $ARG"; exit 22; }
postcat -bh -q "$ARG"
