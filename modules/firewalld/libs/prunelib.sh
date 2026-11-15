#!/bin/bash

##
##   firewalld/libs/prunelib.sh — close what nothing needs open any more.
##
##   firewalld_remove_service is the reverse of firewalld_add_service
##   (firewalldlib.sh); the retired-module clean-up (srvctl/libs/retiredlib.sh)
##   uses it too. prune_firewalld_ports closes the forwarded ports of removed
##   containers: a container's mapped_ports become services named port-N, whose
##   description names the container (generators.mjs, firewall_commands).
##
##   The name in the description only tells that srvctl opened the port for a
##   container; it is not the port's owner: firewalld_add_service keeps an
##   existing service as it is, so a port that moved to another container
##   still carries the first one's name. A port is closed when NO container
##   forwards it any more.
##
##   A service without a name ("added by srvctl"), one that names a local
##   account (opened by hand through firewalld_add_service) and every service
##   not called port-N are the operator's and stay.
##

## TEST SEAM for the selftest, not supported configuration.
: "${SC_FIREWALLD_SERVICE_DIR:=/etc/firewalld/services}"

## Remove service NAME from the permanent configuration of the default zone
## and delete its definition. No reload: the caller reloads once at the end.
function firewalld_remove_service { ## name
    local name="$1" zone file="$SC_FIREWALLD_SERVICE_DIR/$1.xml"

    if [[ ${SC_PRUNE_DRY_RUN:-false} == true ]]
    then
        ntc "Leftover (dry run, not removed): firewalld service $name"
        return 0
    fi

    ## A zone that still lists a service without a definition makes every later
    ## reload fail, so the definition goes only after the zone let go of it.
    zone="$(firewall-cmd --get-default-zone)" || return 1
    if [[ "$(firewall-cmd --zone="$zone" --permanent --query-service="$name")" == yes ]]
    then
        ntc "Removing leftover firewalld service $name"
        logs "prune firewalld service $name"
        firewall-cmd --zone="$zone" --permanent --remove-service="$name" > /dev/null || return 1
    fi
    prune "$file"
}

function prune_firewalld_ports {
    local file text port proto hint ports row rows removed=false
    local -A forwarded

    [[ -n ${SC_PRUNE_CONTAINERS:-} ]] || return 0

    for file in "$SC_FIREWALLD_SERVICE_DIR"/port-*.xml
    do
        [[ -f $file ]] || continue
        text="$(< "$file")"
        [[ $text =~ \<description\>port-([0-9]+)\ (tcp|udp)\ [0-9]+\ \((srvctl\ added\ for|added\ by)\ ([^\)]+)\)\</description\> ]] || continue
        port="${BASH_REMATCH[1]}"
        proto="${BASH_REMATCH[2]}"
        hint="${BASH_REMATCH[4]}"
        [[ $file == */port-"$port".xml ]] || continue
        ## no name, or the account that opened the port by hand
        [[ $hint != srvctl ]] || continue
        ! getent passwd "$hint" > /dev/null || continue

        ## What is forwarded now, read once: the records, and the Port= lines of
        ## the nspawn files, which also cover a container that is not registered.
        if [[ -z ${forwarded[loaded]:-} ]]
        then
            rows="$(list container host_ports)" || return 0
            while IFS=$'\t' read -r _ ports
            do
                for row in $ports
                do
                    forwarded[$row]=yes
                done
            done <<< "$rows"
            while IFS=: read -r row ports _
            do
                forwarded[$row/$ports]=yes
            done < <(sed -n 's/^Port=//p' "$SC_PRUNE_SRV_DIR"/*/*.nspawn 2> /dev/null)
            forwarded[loaded]=yes
        fi
        [[ -z ${forwarded[$proto/$port]:-} ]] || continue

        firewalld_remove_service "port-$port" && removed=true
    done

    [[ ${SC_PRUNE_DRY_RUN:-false} != true ]] || return 0
    $removed && firewall-cmd --reload > /dev/null
}
