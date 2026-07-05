#!/bin/bash

##
##   modules/nfs/hooks/update-install-host.sh — NFS server/client setup.
##
##   Fired by "run_hook update-install-host" during "sc update-install" on
##   a cluster host. Writes /etc/exports, opens the nfs/mountd/rpc-bind
##   firewalld services, mounts the other hosts' shares, then enables and
##   restarts rpcbind and nfs-server (add_service also symlinks the units
##   into /etc/srvctl/system/). All NFS traffic rides the OpenVPN mesh
##   addresses 10.15.<hostnet>.1 — see libs/nfslib.sh.
##

## FIXME(v4): medium — "Install NFS" never installs the nfs-utils package;
## on a minimal Fedora host showmount/mount.nfs are missing, every mount
## check fails, and "add_service nfs-server" ends in "No such service" —
## /etc/exports is written but never served.
msg "Install NFS"

nfs_generate_exports

firewalld_add_service nfs
firewalld_add_service mountd
firewalld_add_service rpc-bind

## FIXME(v4): low — nfs_mount runs before rpcbind/nfs-server are enabled
## below, so on first bootstrap the showmount probes (including to self)
## fail with "Could not mount" errors; mounts only materialize on a later
## regenerate.
nfs_mount

add_service rpcbind
add_service nfs-server
