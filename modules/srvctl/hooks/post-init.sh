#!/bin/bash

##
##   post-init hook — runs on every srvctl invocation, after libs are loaded.
##   Appends the invocation (user, host, cwd, command line) to $SC_LOG
##   (~/.srvctl/srvctl.log). Largely a duplicate of the 'logs' call in init.sh
##   (and of /var/log/srvctl-root.log for root), kept for per-user history.
##

## log commands
echo "$NOW [$SC_USER@$HOSTNAME $(pwd)]# $0 $*" >> "$SC_LOG"

