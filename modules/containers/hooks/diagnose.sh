#!/bin/bash

##
##   containers/hooks/diagnose.sh — container-farm health checks.
##
##   Runs via 'run_hook diagnose' from 'sc diagnose'. Pings 8.8.8.8 and a
##   reference domain from inside every running container
##   (all_containers_pingback, libs/allcontainerslib.sh), shows cgroup
##   memory usage, and verifies the /srv permission contract (0750,
##   drwxr-x--- — set by hooks/update-install-host.sh).
##

all_containers_pingback

run systemd-cgtop -m -n 1

srv_permissions="$(stat -c "%A" /srv)"
if [[ $srv_permissions == "drwxr-x---" ]]
then
    msg "Permissions on /srv OK"
else
    err "Permissions error on /srv $srv_permissions should be drwxr-x---"
    run getfacl /srv
fi