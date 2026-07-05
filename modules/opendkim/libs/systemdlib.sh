#!/bin/bash

##
##   modules/opendkim/libs/systemdlib.sh — service restart helper.
##
##   Sourced by load_libs while the opendkim module is enabled. Provides
##   restart_opendkim, called from regenerate_opendkim after the runtime
##   configuration under /var/opendkim changed: re-asserts ownership,
##   restarts opendkim.service, and reports success or dumps the service
##   status on failure. Same helper shape as in the named, postfix,
##   perdition and saslauthd modules.
##

function restart_opendkim {

    chown -R opendkim:opendkim /var/opendkim

    systemctl restart opendkim.service

    local test
    test=$(systemctl is-active opendkim.service)

    if [[ "$test" == "active" ]]
    then
        msg "restarted opendkim.service"
    else
        err "opendkim restart FAILED!"
        systemctl status opendkim.service --no-pager
    fi
}
