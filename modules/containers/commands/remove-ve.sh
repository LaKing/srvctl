#!/bin/bash

## @@@ remove-ve VE
## @en Back up a container, then remove it with all its files
## &en The container tree is copied to the backup path first
## &en (SC_BACKUP_PATH/srvctl-containers/VE/DATE), then the container is deleted.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
existing_container "$ARG"
owner_only container "$ARG"

remove_ve "$ARG" backup

## sourced context: leave the deleted working directory
cd /srv || return
