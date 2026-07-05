#!/bin/bash

##
##   modules/ssh/libs/mkrootfslib.sh — sshd_config installer for a rootfs.
##
##   Sourced by load_libs while the ssh module is enabled. Provides
##   mkrootfs_sshd_config for container rootfs creation/update and —
##   with '/' as the rootfs — for the host itself
##   (hooks/update-install-host.sh). Note that the containers module's
##   mkrootfs_root_ssh and update_container_sshd_config (libs/bashlib.sh)
##   write the same template: three writers of one file, to be
##   collapsed in v4.
##

## Overwrites <rootfs>/etc/ssh/sshd_config with the module template
## (modules/ssh/sshd_config). Skips with err when the rootfs has no
## sshd_config yet, i.e. no ssh setup is present.
function mkrootfs_sshd_config { ## rootfs

    local rootfs
    rootfs="$1"

    if [[ ! -f "$rootfs/etc/ssh/sshd_config" ]]
    then
        err "No ssh setup present."
        return
    fi

    msg "mkrootfs_ssh_config $rootfs"
    cat "$SC_INSTALL_DIR/modules/ssh/sshd_config" > "$rootfs/etc/ssh/sshd_config"

}
