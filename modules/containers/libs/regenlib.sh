#!/bin/bash

##
##   containers/libs/regenlib.sh — regenerate-time reconciliation between
##   /srv, the datastore and the generated config.
##
##   Used by hooks/regenerate.sh (also hourly via cron) and the
##   regenerate command; restore_uids also by recreate-ve. These
##   functions self-heal the farm: stray directories are imported as
##   containers, missing local containers are created, and generated
##   files (nspawn config, /etc/hosts) are rewritten from the datastore.
##

function regenerate_all_hosts() {
    msg "Regenerate hosts in cluster $SC_CLUSTERNAME"
    for host in $(get cluster host_list)
    do
        msg "regenerate $host"
        if [[ $host == "$HOSTNAME" ]]
        then
            run_hook regenerate
        else
            if ! run ssh -o ConnectTimeout=1 -o BatchMode=yes "$host" "srvctl regenerate" 2> /dev/null
            then
                err "Skipping unreachable host $host"
            fi
        fi

    done

}

function regenerate_etc_hosts() {
    msg "regenerate /etc/hosts"
    ## /etc/hosts is fully generated — manual entries do not survive
    get cluster etc_hosts > /etc/hosts
}


## Walk /srv and reconcile every directory with the datastore:
## import valid-looking strays into the database, re-enable missing
## machines.target wants, and regenerate missing hosts/nspawn config.
function check_container_directories() {
    msg "Checking for containers in directories"
    for D in /srv/*
    do
        if [[ $D == /srv/TEMP ]]
        then
            continue
        fi

        local C

        ## strip /srv
        C="${D:5}"

        if [[ -d $D/rootfs ]]
        then
            
            if [[ "$(get container "$C" exist)" != true ]]
            then
                if [[ -f $D/rootfs/etc/os-release ]]
                then
                    err "Container $C missing from database!"
                    ## AUTOFIX
                    ## C appears to have a valid filesystem
                    local T
                    if [[ -f $D/rootfs/etc/os-release ]]
                    then
                        # shellcheck disable=SC1090,SC1091 ## runtime-path
                        T="$(source "$D/rootfs/etc/os-release" && echo "$ID")"
                    fi
                    
                    
                    new container "$C" "$T"
                    msg "Imported $T $C to database."
                    if [[ -f /srv/$C/ipv4-address ]] && [[ -f /srv/$C/bridge-address ]]
                    then
                        put container "$C" ip "$(cat "/srv/$C/ipv4-address")"
                        put container "$C" br "$(cat "/srv/$C/bridge-address")"
                    else
                        create_nspawn_container_config "$C"
                    fi
                fi
                
            fi
            
            
            if [[ -d /srv/$C/rootfs/etc ]]
            then
                if [[ ! -e "/etc/systemd/system/machines.target.wants/srvctl-nspawn@$C.service" ]]
                then
                    run systemctl enable "srvctl-nspawn@$C"
                fi
                
                if [[ ! -f /srv/$C/hosts ]] || [[ ! -f /srv/$C/$C.nspawn ]]
                then
                    msg "Updating container configuration for $C"
                    
                    #cfg container "$C" update_ip
                    create_nspawn_container_config "$C"
                fi
            fi
            
        fi

        ## if container has everything but a rootfs
        ## FIXME(v4): runs for ANY /srv entry without rootfs/ (only
        ## /srv/TEMP is excluded) — for an unknown directory the datastore
        ## type is empty and create_nspawn_container_filesystem copies ALL
        ## base images into it (see the FIXME there); the stray then gets
        ## imported as a container on the next regenerate.
        if [[ ! -d $D/rootfs ]]
        then
            create_nspawn_container_filesystem "$C"
        fi
    done
}

## Create containers that the database assigns to this host but are
## missing from the local /srv.
function check_container_database() {
    msg "Checking for containers in the database"
    local container_list h
    container_list="$(get cluster container_list)"
    for C in $container_list
    do
        h="$(get container "$C" host)"
        if [[ "$h" == "$HOSTNAME" ]]
        then
            ## this container should be on that host
            if ! [[ -d /srv/$C ]]
            then
                msg "Create local container"
                create_container_configuration_files "$C"
                create_nspawn_container_filesystem "$C"
                create_nspawn_container_config "$C"
            fi
        fi
    done
}

## Repair containers whose internal IP does not match their owner's
## user-based address (stop, re-derive IP, regenerate config, start).
function check_container_ownership() {
    msg "Checking for container owners in the database"
    local container_list
    container_list="$(get cluster container_list)"
    for C in $container_list
    do
        ## FIXME(v4): '[[ $(get ...) ]]' is true for BOTH 'true' and
        ## 'false' output, so the repair branch below is unreachable —
        ## mismatched container IPs are never fixed.
        if [[ $(get container "$C" user_ip_match) ]]
        then
            continue
        else
            msg "Re-setting internal IP of $C due to false user_ip_match"

            run systemctl stop srvctl-nspawn@"$C"
            cfg container "$C" update_ip

            create_nspawn_container_config "$C"

            run systemctl start srvctl-nspawn@"$C" --no-pager -n 30
            run systemctl status srvctl-nspawn@"$C" --no-pager -n 30
        fi
    done
}

## Re-apply datastore-recorded uid/gid ownership: the datastore renders a
## chown script into /srv/$C/restore-uids.sh which is sourced in-shell.
function restore_uids() { ## C
    local C
    C="$1"

    msg "chown container $C filesystem to restore uids and gids on common folders."
    get container "$C" useruids > /srv/"$C"/restore-uids.sh
    # shellcheck disable=SC1090 ## generated-file
    source /srv/"$C"/restore-uids.sh

}