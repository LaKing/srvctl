#!/bin/bash

if $SC_USE_GLUSTER
then
    gluster_configure srvctl-data "$SC_DATASTORE_RW_DIR"
fi
