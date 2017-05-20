#!/bin/bash

## detect virtualization
readonly SC_VIRT=$(systemd-detect-virt -c)

## containers dir is /srv - fixed

# shellcheck disable=SC2034
[[ $ROOTFS_DIR ]] || ROOTFS_DIR=/var/srvctl3-rootfs

# shellcheck disable=SC2034
[[ $MOUNTS_DIR ]] || MOUNTS_DIR=/var/srvctl3-mounts
