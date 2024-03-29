#!/bin/bash

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
