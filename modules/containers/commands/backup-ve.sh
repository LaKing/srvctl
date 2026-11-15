#!/bin/bash

## @@@ backup-ve VE
## @en backup container with all its files
## &en Create a system-backup of the container

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/backup-ve.sh — full-file backup of one container.
##
##   Host-side. Verifies the datastore record exists, escalates via
##   sudomize when the caller owns the container (or is its reseller),
##   then delegates to backup_ve (libs/backupcontainerlib.sh): writes
##   container.json plus package lists into /srv/$C and rsyncs the whole
##   tree to $SC_BACKUP_PATH/srvctl-containers/$C/$NOW — locally, or on
##   $SC_BACKUP_HOST over ssh when that is configured.
##

argument container
existing_container "$ARG"
owner_only container "$ARG"
not_domain_only "$ARG" "a backup of container files" || exit 22

backup_ve "$ARG"
