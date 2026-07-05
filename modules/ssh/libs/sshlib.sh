#!/bin/bash

##
##   modules/ssh/libs/bashlib.sh — ssh hook entry points.
##
##   Sourced by load_libs on every srvctl invocation while the ssh
##   module is enabled. Provides the entry points of the module's two
##   hooks (regenerate_ssh_config, update_install_ssh_config), both
##   built around ssh_main (libs/sshlib.sh), plus the unused
##   update_container_sshd_config.
##

## Entry point of hooks/regenerate.sh. Purges authorized_keys files
## dropped by other modules into the per-container share dirs, then
## runs the full ssh.js pass (ssh_config.d drop-ins, cluster host-key
## scan, known_hosts files, user public-key distribution).
function regenerate_ssh_config() {
    msg "regenerate ssh configs"

    ## FIXME(v4): high — key revocation never propagates: only files literally
    ## named authorized_keys are purged here, while the <user>-*.pub copies made
    ## by ssh.js copy_user_key are never deleted (not even by remove-ve), so a
    ## user removed from a container, or a revoked .pub, keeps root login there
    ## indefinitely via sshd_authorization.sh.
    rm -fr /var/srvctl3/share/containers/*/users/*/authorized_keys

    ssh_main
}

## Entry point of hooks/update-install-host.sh, host only: containers
## have no SC_HOSTNET and must never get the host treatment. Sets up
## the ssh config dirs, runs the full ssh.js pass, installs the module
## sshd_config, seeds /var/srvctl3/share/common/authorized_keys from
## the root authorized_keys, fixes permissions and enables+restarts
## sshd. The exit status of the final 'run systemctl status sshd'
## becomes the hook's exit status (non-zero fails 'sc update-install'
## via run_hook's exif).
function update_install_ssh_config() {

    if [[ ! $SC_HOSTNET ]]
    then
        return
    fi

    msg "Update-install ssh configurations."

    ## we could store host_keys in our datastore (as well). But we wont. At least not for now.

    mkdir -p /etc/ssh/ssh_config.d
    mkdir -p /var/srvctl3/share/common
    mkdir -p /var/srvctl3/ssh
    ssh_main

    ## authorized keys
    ## we will store keys in the datastore dir and in /etc/srvctl
    ## for that we will use multiple AuthorizedKeysFile entries.

    cat "$SC_INSTALL_DIR/modules/ssh/sshd_config" > /etc/ssh/sshd_config

    ## FIXME(v4): medium — sshd_authorization.sh emits this common file for
    ## every authenticating user (%u is ignored on that line), so any key
    ## imported here can log in as any local account on the host, not just
    ## root, contradicting its "used by root as root" comment.
    if [[ ! -f /var/srvctl3/share/common/authorized_keys ]] && [[ -f /etc/srvctl/data/authorized_keys ]]
    then
        msg "Import root authorized_keys from /etc/srvctl/data dir"
        cat /etc/srvctl/data/authorized_keys > /var/srvctl3/share/common/authorized_keys
    fi

    if [[ ! -f /var/srvctl3/share/common/authorized_keys ]] && [[ -f /root/.ssh/authorized_keys ]]
    then
        msg "Import root authorized_keys from /root/.ssh dir"
        cat /root/.ssh/authorized_keys > /var/srvctl3/share/common/authorized_keys
    fi

    ## FIXME(v4): low — the chown/chmod below run even when neither import
    ## source existed and no known_hosts has been generated yet, printing
    ## errors on a pristine install where those files are absent.
    chown root:root /var/srvctl3/share/common/authorized_keys
    chmod 644 /var/srvctl3/share/common/authorized_keys

    ## users need to access this file
    chmod -R 644 /var/srvctl3/ssh/known_hosts
    chmod +X /var/srvctl3/ssh

    mkdir -p "$SC_DATASTORE_RW_DIR/users"

    run systemctl enable sshd
    run systemctl restart sshd
    run systemctl status sshd --no-pager

}

## Writes the module sshd_config into a container rootfs. No in-tree
## callers — mkrootfs_sshd_config (libs/mkrootfslib.sh) and the
## containers module's mkrootfs_root_ssh do the same job; candidate to
## drop in v4.
function update_container_sshd_config() { ## rootfs
    cat "$SC_INSTALL_DIR/modules/ssh/sshd_config" > "$1"/etc/ssh/sshd_config
}
