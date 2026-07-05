#!/bin/bash

## @@@ exec-all COMMAND
## @en Execute a command on all running containers.
## &en In some cases it might come handy to run a single command on all containers.

sudomize

##
##   containers/commands/exec-all.sh — run one shell command in every
##   running container of the cluster.
##
##   Delegates to all_containers_execute (libs/allcontainerslib.sh):
##   machinectl shell for local containers (via a temp-file wrapper,
##   since 'run' cannot pass quoted arguments), 'ssh HOST srvctl C CMD'
##   for containers hosted elsewhere. Inactive containers are reported
##   and skipped. Root sees the cluster list; users their own.
##

all_containers_execute "$OPAS"
