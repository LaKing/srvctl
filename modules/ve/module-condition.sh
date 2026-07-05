#! /bin/bash

## Module condition, sourced (in a subshell) at init: ve is enabled exactly
## when srvctl runs INSIDE a container (systemd-nspawn or lxc) — the VE-side
## counterpart of the containers module, which disables itself there.
##
## Cross-module API: modules/usersonve/module-condition.sh sources this file
## verbatim as its own condition. It must stay source-able (top-level return)
## and print exactly "true" or "false" as its only stdout.

SC_VIRT=$(systemd-detect-virt -c)

## lxc is deprecated, but we can consider it a container ofc.
if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
then
    echo true
    return
fi

echo false

