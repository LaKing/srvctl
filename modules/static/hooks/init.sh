#!/bin/bash

##
##   modules/static/hooks/init.sh — ensure the static storage tree.
##
##   Runs via 'run_hook init' (init.sh) on every srvctl invocation on
##   enabled hosts. With SC_USE_GLUSTER it mounts the replicated
##   srvctl-storage gluster volume onto /var/srvctl3/storage; otherwise
##   it just creates the local directory. Returns 0 unconditionally, so
##   a failed mount or mkdir never aborts the run.
##
##   G4 (gluster removal): the gluster branch is dead at this commit —
##   the gluster module is hard-disabled, so SC_USE_GLUSTER is never
##   true — and is slated for deletion; only the mkdir path survives.
##

## FIXME(v4): 'if $SC_USE_GLUSTER' with an unset variable expands to an
## empty command list = status 0 = true; a stale modules.conf would call
## the undefined gluster_mount_data (exit 127, masked by the return 0).
if $SC_USE_GLUSTER
then
    gluster_mount_data srvctl-storage /var/srvctl3/storage
else
    mkdir -p /var/srvctl3/storage
fi

return 0
