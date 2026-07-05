#!/bin/bash

##
##   containers/hooks/adjust-service.sh — rewrite container names to
##   their nspawn units in the generic service shorthand.
##
##   Sourced by 'run_hook adjust-service' from modules/srvctl/command.sh
##   (which sets $service and $op) before the generic systemctl handling.
##   If $service names a container directory, escalates/authorizes and
##   substitutes service=srvctl-nspawn@$service; a 'restart' is turned
##   into stop + (the caller's) start because nspawn units cannot restart
##   (systemd#2809). 'sc all-containers OP' is dispatched here as well,
##   to all_containers (libs/statuslib.sh), and exits.
##

## special services
# shellcheck disable=SC2154

## TODO check if user is reseller or user of service

echo "============= SERVICE: $service OP: $op SC_USER $SC_USER SC_UID0: $SC_UID0 ======================"

if [[ -d /srv/$service/rootfs ]]
then
    if $SC_UID0
    then
        ## FIXME(v4): tautological ownership test — the trailing
        ## '|| $SC_UID0' is always true inside this 'if $SC_UID0' branch,
        ## so the AUTH-ERROR / exit 142 path is dead and any user able to
        ## sudomize can start/stop/restart any other user's container.
        if [[ $SC_USER == $(get container "$service" user) ]] || [[ $SC_USER == $(get container "$service" reseller) ]] || $SC_UID0
        then
            msg "AUTH-OK $SC_USER has acceess to $service"
        else
            err "AUTH-ERROR $SC_USER has no access to $service"
            exit 142
        fi
    else
        sudomize
    fi
    ## this is the service name actually for a container
    service="srvctl-nspawn@$service"

    ## containers cant be restarted, they need to be stopped and started then
    ## https://github.com/systemd/systemd/issues/2809
    if [[ $op == restart ]]
    then
        run systemctl stop "$service"
        run sleep 1
    fi
fi


## all-containers
if [[ $service == all-containers ]] && [[ -n "$op" ]] && [[ -f "/etc/systemd/system/srvctl-nspawn@.service" ]]
then
    sudomize

    all_containers "$op"
    exit_0
fi