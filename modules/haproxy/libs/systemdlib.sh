#!/bin/bash

##
##   haproxy/libs/systemdlib.sh — haproxy.service reload/restart helpers.
##
##   Sourced by load_libs when the haproxy module is enabled. Used by
##   regenerate_haproxy_conf (proxylib.sh) after a config re-render.
##   Both helpers tolerate failure: they report it but return success, so
##   a broken proxy does not abort the surrounding regenerate run.
##

## restart_haproxy: full restart; on failure run the config syntax check
## and print the unit status for diagnosis.
function restart_haproxy {

    systemctl restart haproxy.service

    if systemctl is-active haproxy.service
    then
        msg "restarted haproxy.service"
    else
        ## haproxy syntax check
        haproxy -c -f /etc/haproxy/haproxy.cfg

        err "HAproxy restart FAILED!"
        systemctl status haproxy.service --no-pager
    fi

    ## haproxy needs a second to start serving, and we have named asking for data from haproxy ...
    run 'sleep 1'
}

## reload_haproxy: graceful reload (keeps connections); falls back to
## restart_haproxy only when the unit went inactive.
function reload_haproxy {

    ## FIXME(v4): no else branch — if the reload fails while the old
    ## process stays active (typical for an invalid new config), this
    ## still prints 'haproxy.service active' and returns success; the new
    ## config is silently never applied and no syntax check runs.
    if systemctl reload haproxy.service
    then
        msg "reloaded haproxy.service"
    fi

    run 'sleep 1'
    if systemctl is-active haproxy.service
    then
        msg "haproxy.service active"
    else
        err "HAproxy INACTIVE"
        systemctl status haproxy.service --no-pager

        restart_haproxy
    fi

    ## haproxy needs a second to start serving, and we have named asking for data from haproxy ...
    run 'sleep 1'
}