#!/bin/bash

##
##   modules/ssh/hooks/regenerate.sh — refresh ssh configs and keys.
##
##   Sourced by 'run_hook regenerate' from 'sc regenerate'
##   (modules/containers/commands/regenerate.sh) and after add-ve /
##   add-ve-user / add-network-ve / add-codepad. Calls
##   regenerate_ssh_config (libs/bashlib.sh): purges stray
##   authorized_keys files from the per-container share dirs, then runs
##   the full ssh.js pass — ssh_config.d drop-ins, cluster host-key
##   scan, known_hosts files and user public-key distribution. A
##   failure aborts the whole srvctl run via run_hook's exif.
##

regenerate_ssh_config
