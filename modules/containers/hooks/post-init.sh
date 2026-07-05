#!/bin/bash

##
##   containers/hooks/post-init.sh — finalize networking identity vars.
##
##   Runs via 'run_hooks post-init' from init.sh. Defaults SC_HOSTNET
##   (unique per-host 10.x network id, 16-255) to 250 and SC_CLUSTERNAME
##   to test_cluster when host.conf did not provide them, locks the
##   module paths readonly, and exports what the node helpers
##   (datastore/status.js/host-conf.js) need from the environment.
##

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

# shellcheck disable=SC2034
readonly SC_HOSTNET
# shellcheck disable=SC2034
readonly SC_ROOTFS_DIR
# shellcheck disable=SC2034
readonly SC_MOUNTS_DIR

## make these variables accessible to js
export SC_HOSTNET
export SC_CLUSTERNAME

export SC_ROOTCA_HOST
