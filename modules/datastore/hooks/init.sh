#!/bin/bash

##
##   modules/datastore/hooks/init.sh — select the RW or RO datastore.
##
##   Runs at init on enabled hosts. When the gluster module is active
##   (SC_USE_GLUSTER, derived by the module loop in commonlib.sh) it tries
##   to mount the srvctl-data gluster volume onto the RW directory and
##   leaves readonly mode only on success; without gluster the local RW
##   directory is used directly, so readonly mode persists only when a
##   gluster mount fails. Finally init_datastore (libs/datalib.sh) picks
##   the directory, seeds missing json files and exports SC_DATASTORE_DIR.
##

if $SC_USE_GLUSTER
then
    if gluster_mount_data srvctl-data "$SC_DATASTORE_RW_DIR"
    then
        # shellcheck disable=SC2034
        SC_DATASTORE_RO_USE=false
    fi
else
    # shellcheck disable=SC2034
    SC_DATASTORE_RO_USE=false
fi

init_datastore
