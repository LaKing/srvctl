#!/bin/bash

##
##   modules/sshpiperd/libs/sshpiperlib.sh — datastore bindfs view.
##
##   Sourced into the shell via load_libs whenever the sshpiperd module
##   is enabled. Provides mount_sshpiper, called only by this module's
##   own hooks (regenerate.sh and update-install-host.sh).
##

## mount_sshpiper
## Idempotently bind-mount a read-only view of the datastore users dir
## at /var/sshpiper — the sshpiperd daemon's working directory, where it
## reads <user>/*.pub and <user>/srvctl_id_ecdsa. bindfs remaps root
## ownership to the unprivileged sshpiper user and adds +X so the daemon
## can traverse the per-user directories; file permissions must stay
## 0600-equivalent through this view (the daemon enforces a 0077 check
## on the mapped private key).
function mount_sshpiper() {

    if mount | grep "on /var/sshpiper type fuse" > /dev/null
    then
        debug "/var/sshpiper is mounted"
    else
        ## FIXME(v4): hook-time mount only — no fstab entry or .mount
        ## unit, so after a reboot /var/sshpiper is empty (all sshpiperd
        ## auth fails) until the hourly regenerate cron remounts it.
        ## FIXME(v4): hardcodes /var/srvctl3/datastore/users instead of
        ## $SC_DATASTORE_RW_DIR/users.
        run bindfs -r -p +X --map=root/sshpiper "/var/srvctl3/datastore/users" /var/sshpiper
    fi

}
