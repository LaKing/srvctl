#!/bin/bash

##
##   modules/nfs/hooks/diagnose.sh — NFS share visibility check.
##
##   Fired by "run_hook diagnose" during "sc diagnose". For every host in
##   the cluster: ping it by hostname, and on success list its NFS exports
##   with showmount. Read-only, no side effects.
##
##   The explicit "return 0" at the end is load-bearing: run_hook wraps
##   each sourced hook in exif (commonlib.sh), so a leaked nonzero status
##   here would abort the whole srvctl run.
##

## FIXME(v4): low — pings $host by DNS name (public route) while actual NFS
## traffic uses the OpenVPN mesh IP 10.15.<hostnet>.1 (nfslib.sh); the
## diagnostic can pass on a path NFS does not use, or fail while the VPN
## path is fine.
msg "-- NFS host shares --"
for host in $(get cluster host_list)
do
    if run timeout 1 ping -c 1 -W 1 "$host"
    then
        ## FIXME(v4): low — no timeout here (unlike the probes in
        ## nfslib.sh); a host that answers ping but filters RPC stalls
        ## sc diagnose for the full RPC timeout per host.
        run showmount -e "$host"
    else
        err "Ping of $host failed"
    fi
done

return 0
