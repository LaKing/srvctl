#!/bin/bash

## Per-user directories (.password, .hash, id_ecdsa) and cert/ (private keys)
## are read only by root. users/ itself and its inventory stay public.
## Do not chmod the read-only fallback when the writable datastore is unavailable.
if [[ ${SC_DATASTORE_RO_USE:-false} == true || ${SC_DATASTORE_RO:-false} == true ]]
then
    return 0
fi

if [[ -d $SC_DATASTORE_DIR/users && ! -L $SC_DATASTORE_DIR/users ]]
then
    find "$SC_DATASTORE_DIR/users" -mindepth 1 -maxdepth 1 -type d ! -perm 0700 -exec chmod 0700 {} + || return 1
fi
if [[ -d $SC_DATASTORE_DIR/cert && ! -L $SC_DATASTORE_DIR/cert ]]
then
    chmod 0700 "$SC_DATASTORE_DIR/cert" || return 1
fi
