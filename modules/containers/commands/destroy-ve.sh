#!/bin/bash

## @@@ destroy-ve VE
## @en Delete a container with all its files, without a backup
## &en Deletes every file and every record of the VE. remove-ve makes a backup first.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
existing_container "$ARG"
owner_only container "$ARG"

remove_ve "$ARG"

## sourced context: leave the deleted working directory
cd /srv || return
