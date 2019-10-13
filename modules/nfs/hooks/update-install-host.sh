#!/bin/bash

msg "Install NFS"

nfs_generate_exports

firewalld_add_service nfs
firewalld_add_service mountd
firewalld_add_service rpc-bind

nfs_mount

add_service rpcbind
add_service nfs-server
