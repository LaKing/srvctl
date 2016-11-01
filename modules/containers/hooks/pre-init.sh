#!/bin/bash

## detect virtualization
readonly SC_VIRT=$(systemd-detect-virt -c)

## lxc is deprecated, but we can consider it a container ofc.
if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
then
    readonly SC_ON_VE=true
else
    readonly SC_ON_VE=false
fi

# shellcheck disable=SC2034
SC_ON_HS=false
## containers dir
# shellcheck disable=SC2034
SRV=/srv
# shellcheck disable=SC2034
ROOTFS_DIR=/var/srvctl3-rootfs
# shellcheck disable=SC2034
MOUNTS_DIR=/var/srvctl3-mounts
