#!/bin/bash

## @@@ add-ve NAME
## @en Add a fedora container.
## &en Generic container for customization.
## &en Contains basic packages.

argument container-name
sudomize
authorize

local C T
C="$ARG"
T="fedora"

if [[ ! -d $SC_ROOTFS_DIR/$T ]]
then
    err "No base for rootfs $T. Please run: srvctl regenerate-rootfs"
    exit
fi

if [[ "$(get container "$C" exist)" == true ]]
then
    err "$C already exists in the system! Exiting"
    exit 11
fi

## check for a mistake
if [[ -d /srv/$C ]]
then
    err "/srv/$C already exists! Exiting"
    exit 11
fi

## add to database
new container "$C" "$T" || exit

## make local container
create_nspawn_container_filesystem "$C" "$T"
create_nspawn_container_network "$C" "$T"

create_selfsigned_domain_certificate "$C" "/srv/$C/cert"
cat "/srv/$C/cert/$C.crt" > "/srv/$C/rootfs/etc/pki/tls/certs/localhost.crt"
cat "/srv/$C/cert/$C.key" > "/srv/$C/rootfs/etc/pki/tls/private/localhost.key"

setup_index_html "$C" "/srv/$C/rootfs"
ln -s "/srv/$C/rootfs/usr/lib/systemd/system/httpd.service" "/srv/$C/rootfs/etc/systemd/system/multi-user.target.wants/httpd.service"

run systemctl start "srvctl-nspawn@$C" --no-pager
run systemctl status "srvctl-nspawn@$C" --no-pager

run_hook regenerate


