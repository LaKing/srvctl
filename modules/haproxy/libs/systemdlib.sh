#!/bin/bash

##
##   haproxy/libs/systemdlib.sh — haproxy.service reload/restart helpers.
##
##   Sourced by load_libs when the haproxy module is enabled. Used by
##   regenerate_haproxy_conf (proxylib.sh) after a config re-render.
##   restart_haproxy tolerates failure: it reports it but returns success,
##   so a broken proxy does not abort the surrounding regenerate run.
##   reload_haproxy reports it and returns non-zero, which its only caller
##   tests (it records the certificate set only after a successful reload).
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
## restart_haproxy only when the unit went inactive. Returns 0 only when the
## new configuration and certificates are actually loaded: the reload
## succeeded, or the fallback restart left the unit active.
function reload_haproxy {
    local loaded=0

    ## FIXME(v4): no syntax check runs before the reload. A failed reload
    ## while the old process stays active (typical for an invalid new
    ## config) is reported and returned, but the old config keeps serving.
    if systemctl reload haproxy.service
    then
        msg "reloaded haproxy.service"
    else
        err "HAproxy reload FAILED, the previous configuration is still serving"
        loaded=1
    fi

    run 'sleep 1'
    if systemctl is-active haproxy.service
    then
        msg "haproxy.service active"
    else
        err "HAproxy INACTIVE"
        systemctl status haproxy.service --no-pager

        restart_haproxy
        if systemctl is-active --quiet haproxy.service
        then
            loaded=0
        else
            loaded=1
        fi
    fi

    ## haproxy needs a second to start serving, and we have named asking for data from haproxy ...
    run 'sleep 1'
    return "$loaded"
}