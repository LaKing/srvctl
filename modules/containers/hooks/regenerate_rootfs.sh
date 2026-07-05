#!/bin/bash

##
##   containers/hooks/regenerate_rootfs.sh — (re)build the base images.
##
##   Runs via 'run_hook regenerate_rootfs' from 'sc regenerate rootfs'.
##   Builds the fedora base image (host VERSION_ID) under
##   $SC_ROOTFS_DIR/fedora via mkrootfs_fedora_base; other modules add
##   their own images through pre-/post- variants of this hook. The
##   commented lines document the other supported builders
##   (libs/mkrootfs_{debian,ubuntu,arch}.sh) which have no live caller.
##

mkrootfs_fedora_base fedora "systemd-container httpd mod_ssl"
#mkrootfs_fedora_base gnome "systemd-container httpd mod_ssl gnome-tweak-tool tigervnc-server"
#mkrootfs_fedora_base mail
#mkrootfs_debian_base debian
#mkrootfs_ubuntu_base debian
#mkrootfs_arch_base arch