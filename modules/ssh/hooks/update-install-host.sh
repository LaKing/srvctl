#!/bin/bash

##
##   modules/ssh/hooks/update-install-host.sh — set up sshd on the host.
##
##   Sourced by 'run_hooks update-install-host' from 'sc update-install'
##   (modules/srvctl/commands/update-install.sh), host only. First
##   installs the module sshd_config onto the host itself
##   (mkrootfs_sshd_config with '/' as the rootfs, libs/mkrootfslib.sh),
##   then update_install_ssh_config (libs/bashlib.sh) creates the ssh
##   dirs, runs the full ssh.js pass, installs the sshd_config again,
##   imports the root authorized_keys into
##   /var/srvctl3/share/common/authorized_keys, fixes permissions and
##   enables+restarts sshd. The last command's exit status becomes the
##   hook's exit status (non-zero fails update-install via run_hook's
##   exif).
##

mkrootfs_sshd_config /
update_install_ssh_config
