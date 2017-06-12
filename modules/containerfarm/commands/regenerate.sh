#!/bin/bash

## @@@ regenerate [all-hosts|rootfs]
## @en Update configuration settings.
## &en Get all modules to write and overwrite config files with the actual configurations.
## &en The argument all-hosts makes the command perform on all hosts.
## &en The regenerate rootfs command rebuilds the container base images.
## &en

root_only
hs_only

## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

if [[ $ARG == rootfs ]]
then
    msg "Create base images"
    mkrootfs_fedora_base fedora "mc httpd mod_ssl openssl postfix mailx sendmail unzip rsync nfs-utils dovecot wget"
    # mkrootfs_fedora_base apache "mc httpd mod_ssl openssl unzip rsync nfs-utils"
    # mkrootfs_fedora_base codepad "mc httpd mod_ssl openssl postfix mailx sendmail unzip rsync nfs-utils dovecot gzip git-core curl python openssl-devel postgresql-devel wget mariadb-server ShellCheck"
    
    return
fi

if [[ $ARG == all-hosts ]]
then
    regenerate_all_hosts
else
    run_hook regenerate
fi

msg "regenerate done"
