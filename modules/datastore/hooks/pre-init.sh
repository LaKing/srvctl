#!/bin/bash

##
##   modules/datastore/hooks/pre-init.sh — datastore path defaults.
##
##   Runs on every srvctl invocation, after /etc/srvctl/*.conf has been
##   sourced, so site config wins and these lines only fill in unset values:
##   the read-only datastore directory (the gluster mount shared across the
##   cluster), the local read-write directory, and the RO-mode flag, which
##   defaults to readonly until hooks/init.sh proves otherwise.
##   SC_DATASTORE_DIR starts out pointing at the RO copy; init_datastore
##   (libs/datalib.sh) re-selects and exports the final value at init.
##

## defaults to the readonly datastore

# shellcheck disable=SC2034
[[ $SC_DATASTORE_RO_DIR ]] || SC_DATASTORE_RO_DIR=/var/srvctl3/gluster/srvctl-data

# shellcheck disable=SC2034
[[ $SC_DATASTORE_RW_DIR ]] || SC_DATASTORE_RW_DIR=/var/srvctl3/datastore

# shellcheck disable=SC2034
[[ $SC_DATASTORE_RO_USE ]] || SC_DATASTORE_RO_USE=true

# shellcheck disable=SC2034
[[ $SC_DATASTORE_DIR ]] || SC_DATASTORE_DIR="$SC_DATASTORE_RO_DIR"

# shellcheck disable=SC2034
readonly SC_DATASTORE_RO_DIR

# shellcheck disable=SC2034
readonly SC_DATASTORE_RW_DIR
