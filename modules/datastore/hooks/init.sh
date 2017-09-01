#!/bin/bash

if $SC_USE_GLUSTER
then
    if gluster_mount_data srvctl-data "$SC_DATASTORE_RW_DIR"
    then
        # shellcheck disable=SC2034
        SC_DATASTORE_RO_USE=false
    fi
    init_datastore
else
    # shellcheck disable=SC2034
    SC_DATASTORE_RO_USE=false
    init_datastore
fi

