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

## Run one host in a separate srvctl process. The local subprocess is
## intentional: run_hook calls exif (which exits the current shell) on failure,
## preventing regenerate_all_hosts from continuing and reporting every failed
## host. Remote stderr remains visible so failures are diagnosable.
## The controller's plan generation travels with every launch: the child's
## init.sh compares it against the generation it freshly verifies itself and
## refuses (113) before hooks when a publication landed in between, so a host
## can never execute under an inventory or DNS ordering it no longer has.
function _regenerate_cluster_host() {
    local host="$1" expected_sha="${2:-}"

    msg "regenerate $host"
    if [[ $host == "$HOSTNAME" ]]
    then
        run env SC_EXPECTED_CLUSTERS_SHA256="$expected_sha" \
            "$SC_INSTALL_BIN" regenerate
    else
        run ssh -o ConnectTimeout=1 -o BatchMode=yes "$host" \
            "SC_EXPECTED_CLUSTERS_SHA256=$expected_sha srvctl regenerate"
    fi
}

## Read the global DNS publication order from the same election helper used by
## named.js. Keeping this bridge out of Bash prevents role drift between the
## orchestration plane and the generated BIND configuration.
function _dns_topology_hosts() {
    /bin/node "$SC_INSTALL_DIR/modules/named/lib/topology-cli.js" \
        /etc/srvctl/clusters.json
}

## Enumerate every host from the canonical global topology. This deliberately
## does not use `get cluster host_list`: that value is a host-local datastore
## projection and can omit hosts in other clusters (or retain removed hosts).
function _canonical_cluster_hosts() {
    /bin/node "$SC_INSTALL_DIR/modules/containers/lib/cluster-config-cli.js" \
        hosts /etc/srvctl/clusters.json
}

## Hash the complete canonical file, not merely its elected DNS roles. Two
## files can elect the same primary/replicas while disagreeing on hostnets,
## addresses or ordinary hosts, so all-host regeneration requires the exact
## file bytes to agree before changing any machine.
function _canonical_clusters_sha() {
    /bin/node "$SC_INSTALL_DIR/modules/containers/lib/cluster-config-cli.js" \
        sha256 /etc/srvctl/clusters.json
}

function _canonical_clusters_sha_on() {
    local host="$1"
    if [[ $host == "$HOSTNAME" ]]
    then
        _canonical_clusters_sha
    else
        ssh -o ConnectTimeout=1 -o BatchMode=yes "$host" \
            "/bin/node $SC_INSTALL_DIR/modules/containers/lib/cluster-config-cli.js sha256 /etc/srvctl/clusters.json"
    fi
}

## Ask each host which DNS topology its own clusters.json elects. all-hosts
## compares this byte-for-byte before mutating anything, preventing two stale
## host-local configuration files from silently publishing different primaries.
function _dns_topology_hosts_on() {
    local host="$1"
    if [[ $host == "$HOSTNAME" ]]
    then
        _dns_topology_hosts
    else
        ssh -o ConnectTimeout=1 -o BatchMode=yes "$host" \
            "/bin/node $SC_INSTALL_DIR/modules/named/lib/topology-cli.js /etc/srvctl/clusters.json"
    fi
}

function regenerate_all_hosts() {
    local host host_rows host_status role topology_rows topology_status remote_topology
    local canonical_sha checksum_status remote_sha final_sha current_sha
    local publication_primary=""
    local -a hosts=()
    local -a ordinary_hosts=()
    local -a replica_hosts=()
    local -a ordered_hosts=()
    local -a failed_hosts=()
    local -A dns_role=()
    local -A host_seen=()

    msg "Regenerate every host in the canonical cluster topology"

    host_rows="$(_canonical_cluster_hosts)"
    host_status=$?
    if [[ $host_status -ne 0 ]]
    then
        err "Cannot read hosts from /etc/srvctl/clusters.json"
        return "$host_status"
    fi
    while IFS= read -r host
    do
        [[ -n $host ]] || continue
        if [[ ! -v host_seen["$host"] ]]
        then
            hosts+=("$host")
            host_seen["$host"]=1
        fi
    done <<< "$host_rows"

    canonical_sha="$(_canonical_clusters_sha)"
    checksum_status=$?
    if [[ $checksum_status -ne 0 ]]
    then
        err "Cannot checksum /etc/srvctl/clusters.json"
        return "$checksum_status"
    fi
    if [[ ! $canonical_sha =~ ^[0-9a-f]{64}$ ]]
    then
        err "Invalid checksum returned for /etc/srvctl/clusters.json"
        return 1
    fi

    ## all-host regeneration is a consumer of the last successfully published
    ## topology, never an alternate publication path. In particular, an edit
    ## that already omitted an unretired host must not shrink this command's
    ## target set. Compare the stable local SHA/ordered inventory before DNS
    ## preflight, SSH, or any regeneration subprocess.
    if ! declare -F verify_cluster_publication_inventory > /dev/null ||
       ! verify_cluster_publication_inventory "$canonical_sha" "${hosts[@]}"
    then
        err "Canonical cluster topology is not the last successful publication; run publish_data first"
        return 1
    fi

    topology_rows="$(_dns_topology_hosts)"
    topology_status=$?
    if [[ $topology_status -ne 0 ]]
    then
        err "Cannot determine the global DNS publication order"
        return "$topology_status"
    fi

    while IFS=$'\t' read -r role host
    do
        [[ -n $role && -n $host ]] || continue
        case "$role" in
            primary)
                publication_primary="$host"
                dns_role["$host"]="primary"
                ;;
            replica)
                replica_hosts+=("$host")
                dns_role["$host"]="replica"
                ;;
            *)
                err "Invalid DNS topology role '$role' for host $host"
                return 1
                ;;
        esac
    done <<< "$topology_rows"

    ## DNS election rows are derived from this same canonical file, so every
    ## elected authority must also occur in its validated global host list.
    for host in "${!dns_role[@]}"
    do
        if [[ ! -v host_seen["$host"] ]]
        then
            err "DNS topology host $host is missing from the canonical host list"
            return 1
        fi
    done

    ## Full-file agreement and DNS-helper agreement are both capability/data
    ## preflights. A missing new helper on any host, an unreadable file, a
    ## checksum mismatch or a different election aborts before the first
    ## regeneration subprocess is launched.
    for host in "${hosts[@]}"
    do
        remote_sha="$(_canonical_clusters_sha_on "$host")"
        checksum_status=$?
        if [[ $checksum_status -ne 0 ]]
        then
            err "Cannot verify cluster configuration checksum on host $host"
            return "$checksum_status"
        fi
        if [[ ! $remote_sha =~ ^[0-9a-f]{64}$ ]]
        then
            err "Invalid cluster configuration checksum from host $host"
            return 1
        fi
        if [[ $remote_sha != "$canonical_sha" ]]
        then
            err "Cluster configuration mismatch on host $host; synchronize /etc/srvctl/clusters.json"
            return 1
        fi

        remote_topology="$(_dns_topology_hosts_on "$host")"
        topology_status=$?
        if [[ $topology_status -ne 0 ]]
        then
            err "Cannot verify DNS topology on host $host"
            return "$topology_status"
        fi
        if [[ $remote_topology != "$topology_rows" ]]
        then
            err "DNS topology mismatch on host $host; synchronize /etc/srvctl/clusters.json"
            return 1
        fi
    done

    ## Catch an edit or replacement of the initiating host's canonical file
    ## during the remote preflight window. Publication tooling uses an atomic
    ## replace, but this guard also covers an operator editing the file.
    final_sha="$(_canonical_clusters_sha)"
    checksum_status=$?
    if [[ $checksum_status -ne 0 ]]
    then
        err "Cannot recheck /etc/srvctl/clusters.json"
        return "$checksum_status"
    fi
    if [[ $final_sha != "$canonical_sha" ]]
    then
        err "Cluster configuration changed during regeneration preflight"
        return 1
    fi

    ## Preserve canonical cluster/object order for every ordinary host across
    ## every cluster, then publish on the sole primary and finally converge all
    ## replicas. The host list and role maps are globally de-duplicated.
    for host in "${hosts[@]}"
    do
        if [[ ! -v dns_role["$host"] ]]
        then
            ordinary_hosts+=("$host")
        fi
    done

    ordered_hosts+=("${ordinary_hosts[@]}")
    if [[ $publication_primary ]]
    then
        ordered_hosts+=("$publication_primary")
    fi
    ordered_hosts+=("${replica_hosts[@]}")

    for host in "${ordered_hosts[@]}"
    do
        ## A publication landing mid-run would leave this controller driving
        ## generation-A host order and DNS roles while hosts already carry
        ## generation B (each child invocation pins its own generation).
        ## Re-probe the initiating generation before every host and abort
        ## loudly instead of continuing with a stale plan.
        current_sha="$(_canonical_clusters_sha)"
        checksum_status=$?
        if [[ $checksum_status -ne 0 ]]
        then
            err "Cannot recheck /etc/srvctl/clusters.json during all-host regeneration"
            return "$checksum_status"
        fi
        if [[ $current_sha != "$canonical_sha" ]]
        then
            err "Cluster configuration changed during all-host regeneration; retry"
            return 1
        fi
        if ! _regenerate_cluster_host "$host" "$canonical_sha"
        then
            failed_hosts+=("$host")
            err "Regeneration failed on host $host"
        fi
    done

    if [[ ${#failed_hosts[@]} -gt 0 ]]
    then
        err "Regeneration failed on hosts: ${failed_hosts[*]}"
        return 1
    fi

    return 0
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
