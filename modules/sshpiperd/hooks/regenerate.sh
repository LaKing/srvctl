#!/bin/bash

##
##   modules/sshpiperd/hooks/regenerate.sh — keep the bindfs view alive.
##
##   Runs via 'run_hook regenerate' — fired by 'sc regenerate' (incl.
##   the hourly cron installed by the containers module) and by
##   add-ve / add-ve-user / add-codepad / add-network-ve. Re-ensures the
##   read-only bindfs mount of the datastore users dir on /var/sshpiper
##   (mount_sshpiper, libs/sshpiperlib.sh).
##

## FIXME(v4): if mount_sshpiper fails (e.g. bindfs not installed), this
## sourced hook returns non-zero and run_hook's exif aborts the entire
## regenerate run.
mount_sshpiper
