#!/bin/bash

## @@@ add-ve NAME [TYPE]

## @en Add a VE under a domain name, by instantiating from TYPE
## &en Generic container for customization.
## &en Contains basic packages.

## @hu Egy VE létrehozása, TYPE tipusból
## &hu Általánosan használható VE/konténer-környezet elkészítése.
## &hu Csak az alapvető csomagokat tartalmazza.

## &&& ls /var/srvctl3/rootfs


argument container-name
authorize
sudomize

C="$ARG"
T="fedora"

if [[ $OPA ]]
then
    T="$OPA"
fi


if [[ -f "$SC_ROOTFS_DIR/$T/etc/os-release" ]]
then
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