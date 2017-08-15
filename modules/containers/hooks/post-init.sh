#!/bin/bash

readonly SC_HOSTNET
readonly SC_ROOTFS_DIR
readonly SC_MOUNTS_DIR

## make these variables accessible to js
export SC_HOSTNET
export SC_CLUSTERNAME

debug "SC_CLUSTERNAME=$SC_CLUSTERNAME SC_HOSTNET=$SC_HOSTNET"
