#!/bin/bash

## @@@ regenerate-rootfs
## @en Create the container base.
## &en Download container filesystems that will be used as base when creating containers.
## &en

hs_only
root_only

## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

## CREATE BASE IMAGES
msg "Create base images"
mkrootfs_fedora_base fedora "mc httpd mod_ssl openssl postfix mailx sendmail unzip rsync nfs-utils dovecot wget"
mkrootfs_fedora_base apache "mc httpd mod_ssl openssl unzip rsync nfs-utils"
mkrootfs_fedora_base codepad "mc httpd mod_ssl openssl postfix mailx sendmail unzip rsync nfs-utils dovecot gzip git-core curl python openssl-devel postgresql-devel wget mariadb-server ShellCheck"
