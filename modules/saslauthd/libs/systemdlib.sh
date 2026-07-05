#!/bin/bash

## Library sourced globally (via load_libs) whenever the saslauthd module is
## enabled. Provides the restart-and-verify helper used by hooks/regenerate.sh.

## Restart saslauthd.service and report whether it came back up.
function restart_saslauthd {

    local test

    systemctl restart saslauthd.service

    test=$(systemctl is-active saslauthd.service)

    if [[ "$test" == "active" ]]
    then
        msg "restarted saslauthd.service"
    else
        err "saslauthd restart FAILED!"
        systemctl status saslauthd.service --no-pager
    fi

}
