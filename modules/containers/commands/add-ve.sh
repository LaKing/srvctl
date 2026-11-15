#!/bin/bash

## @@@ add-ve NAME [TYPE]

## @en Add a VE under a domain name, by instantiating from TYPE
## &en Generic container for customization.
## &en Contains basic packages.

## &&& ls /var/srvctl3/rootfs

##
##   containers/commands/add-ve.sh — create a new container from a base
##   image. The caller becomes its owner, and its address comes from the
##   caller's network (10.HOSTNET.USER_ID.x), so the caller needs a user
##   record: users_only.
##
##   add_ve (libs/addcontainerlib.sh) validates the name and the type and
##   builds the container: datastore record, /srv/$C tree copied from
##   $SC_ROOTFS_DIR/$T, nspawn config, self-signed cert, index.html,
##   postfix conf, enable+start of srvctl-nspawn@$C. The add-ve,
##   add_ve_$T and regenerate hooks follow (codepad and firewalld hook
##   into these). TYPE defaults to fedora.
##
##   The dynamic-help marker above lists the available base images in
##   the command hint.
##

argument container-name
users_only
sudomize

C="$ARG"
T="${OPA:-fedora}"

msg "Adding $T $C"
add_ve "$T" "$C"

run_hook add-ve
run_hook "add_ve_$T"
run_hook regenerate
