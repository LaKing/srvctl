#!/bin/bash

##
##   modules/perdition/libs/systemdlib.sh — perdition module lib,
##   auto-loaded when the module is enabled.
##
##   restart_perdition restarts the three custom perdition units
##   (imap4s, imap4, pop3s) and verifies each came back up; on failure
##   it prints an error and the service status. It does not exit
##   nonzero itself, but ends with a nonzero status when the last unit
##   is down — callers (hooks/regenerate.sh) must swallow that.
##

function restart_perdition {

    local test

    systemctl restart imap4s.service

    test=$(systemctl is-active imap4s.service)

    if [[ "$test" == "active" ]]
    then
        msg "restarted imap4s.service"
    else
        err "imap4s restart FAILED!"
        systemctl status imap4s.service --no-pager
    fi

    systemctl restart imap4.service

    test=$(systemctl is-active imap4.service)

    if [[ "$test" == "active" ]]
    then
        msg "restarted imap4.service"
    else
        err "imap4 restart FAILED!"
        systemctl status imap4.service --no-pager
    fi

    systemctl restart pop3s.service

    test=$(systemctl is-active pop3s.service)

    if [[ "$test" == "active" ]]
    then
        msg "restarted pop3s.service"
    else
        err "pop3 restart FAILED!"
        systemctl status pop3s.service --no-pager
    fi

}
