#!/bin/bash

##
##   containers/hooks/pre-init.sh — early defaults for module paths.
##
##   Runs via 'run_hooks pre-init' from init.sh before commands and other
##   hooks; /etc/srvctl/*.conf may have set these already. Both become
##   readonly in hooks/post-init.sh.
##

# shellcheck disable=SC2034
[[ $SC_ROOTFS_DIR ]] || SC_ROOTFS_DIR=/var/srvctl3/rootfs

# shellcheck disable=SC2034
[[ $SC_MOUNTS_DIR ]] || SC_MOUNTS_DIR=/var/srvctl3/mounts
