#!/bin/bash

if [[ $SC_HOSTNET ]]
then
    debug "SC_HOSTNET is $SC_HOSTNET"
else
    msg "Setting SC_HOSTNET to 250 as it is undefined so far."
    SC_HOSTNET=250
fi

if [[ $SC_CLUSTERNAME ]]
then
    debug "SC_CLUSTERNAME is $SC_CLUSTERNAME"
else
    msg "Setting SC_CLUSTERNAME to test_cluster as it is undefined so far."
    SC_CLUSTERNAME=test_cluster
fi

readonly SC_HOSTNET
readonly SC_ROOTFS_DIR
readonly SC_MOUNTS_DIR

## make these variables accessible to js
export SC_HOSTNET
export SC_CLUSTERNAME

export SC_ROOTCA_HOST
