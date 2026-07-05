#!/bin/bash

##
##   modules/postfix/libs/systemdlib.sh — postfix service control.
##
##   Sourced via load_libs when SC_USE_POSTFIX=true.
##

## restart_postfix
## Restart postfix.service and verify it came back up; on failure run
## 'postfix check' (syntax report), print an error and the service status.
function restart_postfix {

    local test

    systemctl restart postfix.service

    test=$(systemctl is-active postfix.service)

    if [[ "$test" == "active" ]]
    then
        msg "restarted postfix.service"
    else
        ## syntax check
        postfix check

        err "Postfix restart FAILED!"
        ## FIXME(v4): medium — on failure the function ends with this
        ## status call (exit 3), so the regenerate hook returns nonzero
        ## and run_hook's exif aborts the entire invoking command —
        ## a broken postfix kills add-ve/add-ve-user/add-codepad/
        ## regenerate mid-flow, leaving half-built containers.
        systemctl status postfix.service --no-pager
    fi
}
