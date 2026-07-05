#!/bin/bash

##
##   codepad regenerate_rootfs hook — sourced by run_hook
##   regenerate_rootfs from 'sc regenerate rootfs' (containers module).
##   Rebuilds the codepad template rootfs ($SC_ROOTFS_DIR/codepad) from
##   scratch. Runs BEFORE the containers module's own hook (module glob
##   order: codepad < containers).
##

mkrootfs_fedora_install_codepad
