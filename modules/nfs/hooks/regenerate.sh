#!/bin/bash

##
##   modules/nfs/hooks/regenerate.sh — re-mount all cluster NFS shares.
##
##   Fired by "run_hook regenerate" — from "sc regenerate" and from the
##   add-ve / add-ve-user / add-network-ve flows — so it runs often and
##   must stay cheap and non-fatal (see nfs_mount in libs/nfslib.sh).
##   Mounts ride the OpenVPN mesh addresses 10.15.<hostnet>.1.
##
## FIXME(v4): smell — never re-generates /etc/exports (only update-install
## restores it), and the mounts are runtime-only (no fstab/automount/systemd
## units), so remote shares are absent after a reboot until a regenerate
## runs.

nfs_mount
