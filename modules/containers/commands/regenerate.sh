#!/bin/bash

## @@@ regenerate [all-hosts|rootfs]
## @en Update configuration settings.
## &en Get all modules to write and overwrite config files with the actual configurations.
## &en The argument all-hosts makes the command perform on all hosts.
## &en The regenerate rootfs command rebuilds the container base images.
## &en

## WP-E.2.b: host-wide config regeneration -> root only (was commented out).
root_only
hs_only

## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/regenerate.sh — rewrite all generated
##   configuration from the datastore.
##
##   Three modes:
##     (no arg)    run_hook regenerate — every enabled module rewrites its
##                 config files; this module's hooks/regenerate.sh checks
##                 /srv dirs vs the database, ownership, /etc/hosts and
##                 the inotify sysctl
##     all-hosts   regenerate_all_hosts — same, plus 'srvctl regenerate'
##                 over ssh on every other cluster host
##     rootfs      run_hook regenerate_rootfs — rebuild the container base
##                 images under /var/srvctl3/rootfs (from /root as cwd)
##
##   Also invoked hourly by cron as: srvctl regenerate '#cron.hourly'
##   (installed by hooks/update-install-host.sh); hooks/regenerate.sh
##   matches that literal ARG to run the container quota check.
##

if [[ $ARG == rootfs ]]
then
    ## dnf/debootstrap runs want a stable cwd
    # shellcheck disable=SC2164 ## run-wrapped
    run cd /root

    msg "Create base images"

    run_hook regenerate_rootfs
    return
fi

if [[ $ARG == all-hosts ]]
then
    regenerate_all_hosts
else
    run_hook regenerate
fi

msg "regenerate done"
