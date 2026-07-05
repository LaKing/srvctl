#!/bin/bash

## update-install hook: fired via run_hooks update-install-host from the
## srvctl update-install command. This module is VE-only (see
## module-condition.sh), so despite the -host suffix it only ever runs INSIDE
## containers: every `sc update-install` executed in a container performs a
## full package update of that container.

## FIXME(v4): misnamed (-host, but VE-side only), and a full dnf update as a
## side effect of update-install is slow and surprising; rename the hook and
## consider gating the update behind an explicit flag.
run dnf -y update
