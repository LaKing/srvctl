#!/bin/bash

## @@@ add-ve NAME [TYPE]

## @en Add a VE under a domain name, by instantiating from TYPE
## &en Generic container for customization.
## &en Contains basic packages.

## @hu Egy VE létrehozása, TYPE tipusból
## &hu Általánosan használható VE/konténer-környezet elkészítése.
## &hu Csak az alapvető csomagokat tartalmazza.

## &&& ls /var/srvctl3/rootfs

##
##   containers/commands/add-ve.sh — create a new container from a base
##   image.
##
##   Validates the domain-style name, escalates to root (sudomize), then
##   calls add_ve (libs/addcontainerlib.sh): datastore record, /srv/$C
##   tree copied from $SC_ROOTFS_DIR/$T, nspawn config, self-signed cert,
##   index.html, postfix conf, and enable+start of srvctl-nspawn@$C.
##   Afterwards runs the add-ve, add_ve_$T and regenerate hooks (codepad
##   and firewalld modules hook into these). TYPE defaults to fedora; a
##   missing base image lists the available types instead.
##
##   The dynamic-help marker above lists the available base images in
##   the command hint.
##

argument container-name
## WP-E.2.b: provisioning a container is an operator/root action (was the
## non-denying authorize stub). The created container is then owned by a user.
operators_only
sudomize

C="$ARG"
T="fedora"

if [[ $OPA ]]
then
    T="$OPA"
fi


if [[ -f "$SC_ROOTFS_DIR/$T/etc/os-release" ]]
then
    ## FIXME(v4): sourcing the template os-release into the running shell
    ## overwrites the host's ID/VERSION_ID (sourced by init.sh) for every
    ## hook that runs later in this same invocation.
    # shellcheck source=/dev/null
    source "$SC_ROOTFS_DIR/$T/etc/os-release"
    msg "Adding $T $C"
    add_ve "$T" "$C"
    
    run_hook add-ve
    run_hook "add_ve_$T"
    run_hook regenerate
else
    err "The requested container type $OPA is not present on this system. Currently available types are:"
    ls "$SC_ROOTFS_DIR"
fi