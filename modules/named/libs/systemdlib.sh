#!/bin/bash

##
##   modules/named/libs/systemdlib.sh — named module lib, auto-loaded
##   when the module is enabled.
##
##   restart_named restarts named.service and verifies it came back up;
##   on failure it runs named-checkconf (syntax report on stdout), prints
##   an error and the service status. It does not exit nonzero itself —
##   the srvctl run continues.
##

function restart_named {

    local test

    systemctl restart named.service

    test=$(systemctl is-active named.service)

    if [[ "$test" == "active" ]]
    then
        msg "restarted named.service"
    else
        ## syntax check
        named-checkconf

        err "named restart FAILED!"
        systemctl status named.service --no-pager
    fi
}
