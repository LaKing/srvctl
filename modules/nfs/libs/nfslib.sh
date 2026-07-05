#!/bin/bash

##
##   modules/nfs/libs/nfslib.sh — cluster-internal /srv sharing over NFS.
##
##   Sourced by load_libs whenever SC_USE_NFS=true (the nfs module condition
##   mirrors the containers module, so every cluster host participates —
##   there is no independent opt-out). Each host exports its /srv and mounts
##   every cluster host's /srv, so other modules (notably usersonhost) can
##   reach containers that live on remote hosts.
##
##   Cross-module contracts (must not change):
##     - mount path /var/srvctl3/nfs/<host>/srv — consumed verbatim by
##       modules/usersonhost/main.js
##     - export line "/srv 10.15.0.0/255.255.0.0(rw,no_root_squash)" —
##       peers mount 10.15.<hostnet>.1:/srv, so /srv must stay export root
##
##   Network dependency: both the reachability probes and the mount sources
##   use the OpenVPN mesh addresses 10.15.<hostnet>.1 (hostnet read from
##   datastore key "host <name> hostnet"). The v4 zerotier migration must
##   rework the export network and the mount sources here together.
##

## Overwrite /etc/exports with the single cluster-wide /srv export.
## Does not run exportfs -r itself; relies on the nfs-server restart that
## follows in hooks/update-install-host.sh.
## FIXME(v4): low — clobbers the whole /etc/exports, silently destroying any
## admin-maintained export lines on the host.
## FIXME(v4): security — /srv is exported rw,no_root_squash to the entire
## 10.15.0.0/16 mesh; any compromised cluster member gains root-equivalent
## write access to every other host's /srv.
function nfs_generate_exports {

cat > /etc/exports << EOF
## $SRVCTL generated
/srv 10.15.0.0/255.255.0.0(rw,no_root_squash)
EOF

}

## Mount every cluster host's /srv under /var/srvctl3/nfs/<host>/srv.
## Called from hooks/regenerate.sh (sc regenerate and every add-ve /
## add-ve-user / add-network-ve flow) and hooks/update-install-host.sh,
## so it must stay cheap and non-fatal: every failure goes through err
## and the loop continues. The 1-second probe timeouts bound regenerate
## latency per unreachable host.
function nfs_mount() {

    msg "nfs mount"

    local host hs
    ## FIXME(v4): medium — no "$host == $HOSTNAME" skip, so each host
    ## NFS-loopback-mounts its own /srv; no consumer uses the local-host
    ## path, and loopback NFS mounts are deadlock-prone under memory
    ## pressure.
    for host in $(get cluster host_list)
    do
        hs="$(get host "$host" hostnet)"
        msg "openvpn connection check to $host ($hs)"
        if run timeout 1 ping -c 1 -W 1 "10.15.$hs.1" > /dev/null
        then
            ## the double space in this message is the existing logged
            ## string; kept verbatim
            msg "mount check on  $host ($hs)"
            if run timeout 1 showmount -e "$host" > /dev/null
            then
                ## timeout guards against mkdir hanging on a stale NFS
                ## mountpoint; its result is not checked
                run timeout 1 mkdir -p "/var/srvctl3/nfs/$host/srv"
                ## FIXME(v4): medium — no already-mounted check; every
                ## regenerate stacks another NFS mount on the same target
                ## (or emits a spurious eyif warning), so long-lived hosts
                ## accumulate duplicate mounts.
                run "mount 10.15.$hs.1:/srv /var/srvctl3/nfs/$host/srv"
            else
                ## FIXME(v4): smell — misleading text: the step that failed
                ## is the showmount probe, not the mount itself.
                err "Could not mount $host 10.15.$hs.1"
            fi
        else
            err "Could not ping $host on 10.15.$hs.1"
        fi
    done
}
