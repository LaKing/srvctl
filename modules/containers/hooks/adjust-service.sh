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

echo "============= SERVICE: $service OP: $op SC_USER $SC_USER SC_UID0: $SC_UID0 ======================"

if [[ -d /srv/$service/rootfs ]]
then
    ## WP-E.2.b audit: default container service shorthand (`sc VE restart`,
    ## `sc restart VE`, etc.) is owner-scoped too. The old path sudomized before
    ## checking ownership, then root always passed; non-owners could operate
    ## other users' containers.
    owner_only container "$service"
    msg "AUTH-OK $SC_USER has access to $service"

    ## Capability token for command.sh's generic host-service root gate: THIS
    ## action has been owner-authorized, so that gate must NOT re-deny it. It is
    ## keyed on this flag, NOT on the srvctl-nspawn@ name — a user can type
    ## `sc srvctl-nspawn@victim stop` directly, which never reaches this hook
    ## and so never gets the token. Set only AFTER owner_only returns.
    # shellcheck disable=SC2034
    SC_SERVICE_OWNER_AUTHORIZED=true

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
    root_only

    all_containers "$op"
    exit_0
fi
