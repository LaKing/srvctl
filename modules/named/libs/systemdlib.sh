#!/bin/bash

##
##   modules/named/libs/systemdlib.sh — named module lib, auto-loaded
##   when the module is enabled.
##
##   restart_named validates the complete BIND configuration before touching
##   the running service, restarts named, waits briefly for its rndc control
##   channel, then explicitly propagates every srvctl-managed zone:
##     - master zones send NOTIFY
##     - slave zones force + verify a full retransfer for convergence runs
##       (the hourly safety run requests a lightweight refresh)
##   Every failure is reported and returned to the regenerate hook. Zone
##   actions continue after an individual failure so one broken zone does not
##   hide the state of the rest.
##

## Print "<type><TAB><zone>[<TAB><primary-address>]" for the master/slave
## zones declared by the generated include. The generator emits one
## declaration per line, including one masters/primaries address for replicas.
## Comments and non-replicated zone types are ignored.
function named_managed_zones {
    local conf
    conf="${1:-/var/named/srvctl.conf}"

    if [[ ! -r $conf ]]
    then
        err "Cannot read managed named configuration $conf"
        return 1
    fi

    awk '
        /^[[:space:]]*(#|\/\/)/ { next }
        /^[[:space:]]*zone[[:space:]]*"/ {
            split($0, quoted, "\"")
            zone = quoted[2]
            type = ""
            primary = ""
            if ($0 ~ /type[[:space:]]+master([[:space:]]|;)/) type = "master"
            if ($0 ~ /type[[:space:]]+slave([[:space:]]|;)/) type = "slave"
            if (type == "slave" &&
                $0 ~ /(masters|primaries)[[:space:]]*\{[[:space:]]*[^;[:space:]]+/) {
                primary = $0
                sub(/^.*(masters|primaries)[[:space:]]*\{[[:space:]]*/, "", primary)
                split(primary, address, /[;[:space:]]/)
                primary = address[1]
            }
            if (zone != "" && type != "" && !seen[type SUBSEP zone]++) {
                if (type == "slave") print type "\t" zone "\t" primary
                else print type "\t" zone
            }
        }
    ' "$conf"
}

## A successful systemd restart can return before named has opened its rndc
## control channel. Poll it for at most ten seconds; callers may override this
## helper in isolated tests without sleeping or contacting a real daemon.
function named_wait_rndc_ready {
    local attempt

    for ((attempt = 1; attempt <= 10; attempt++))
    do
        if rndc status > /dev/null 2>&1
        then
            return 0
        fi

        if (( attempt < 10 ))
        then
            sleep 1
        fi
    done

    err "named rndc control channel did not become ready"
    return 1
}

## Query one authoritative SOA and assign its serial to the caller-provided
## variable name. An empty/SERVFAIL response is a verification failure even
## when dig itself exits zero.
function named_query_soa_serial {
    local result_variable server zone answer mname rname serial
    result_variable="$1"
    server="$2"
    zone="$3"

    if ! answer="$(dig +time=1 +tries=1 +norecurse +short "@$server" "$zone" SOA)"
    then
        return 1
    fi

    read -r mname rname serial _ <<< "$answer"
    if [[ -z $mname || -z $rname || ! $serial =~ ^[0-9]+$ ]]
    then
        return 1
    fi

    printf -v "$result_variable" '%s' "$serial"
}

## Return a process-monotonic timestamp. Keeping this behind a helper makes the
## convergence deadline deterministic in selftests without weakening the real
## wall-clock bound.
function named_monotonic_seconds {
    printf '%s\n' "$SECONDS"
}

## Calculate one global replica-convergence deadline. BIND permits two inbound
## transfers per remote nameserver by default (transfers-per-ns), so many zones
## sharing one primary are queued rather than transferred at once. Allow five
## seconds for each queue batch in addition to a ten-second startup allowance.
## The result remains capped, and every tuning value can be overridden for an
## unusually large/slow installation without changing this library.
function named_replica_convergence_timeout {
    local result_variable pair zone primary count max_count=0 batches computed_timeout
    local slots="${NAMED_REPLICA_TRANSFERS_PER_NS:-2}"
    local base_seconds="${NAMED_REPLICA_BASE_SECONDS:-10}"
    local batch_seconds="${NAMED_REPLICA_BATCH_SECONDS:-5}"
    local max_seconds="${NAMED_REPLICA_MAX_SECONDS:-300}"
    local override_seconds="${NAMED_REPLICA_TIMEOUT_SECONDS:-}"
    declare -A primary_counts=()
    result_variable="$1"
    shift

    for count in "$slots" "$base_seconds" "$batch_seconds" "$max_seconds"
    do
        if [[ ! $count =~ ^[1-9][0-9]*$ ]]
        then
            err "Invalid named replica convergence timing value: $count"
            return 1
        fi
    done
    if [[ -n $override_seconds && ! $override_seconds =~ ^[1-9][0-9]*$ ]]
    then
        err "Invalid NAMED_REPLICA_TIMEOUT_SECONDS: $override_seconds"
        return 1
    fi

    for pair in "$@"
    do
        IFS=$'\t' read -r zone primary <<< "$pair"
        [[ -n $zone && -n $primary ]] || continue
        count=$(( ${primary_counts[$primary]:-0} + 1 ))
        primary_counts["$primary"]="$count"
        (( count > max_count )) && max_count="$count"
    done

    if [[ -n $override_seconds ]]
    then
        computed_timeout="$override_seconds"
    else
        batches=$(( (max_count + slots - 1) / slots ))
        computed_timeout=$(( base_seconds + batches * batch_seconds ))
    fi
    (( computed_timeout > max_seconds )) && computed_timeout="$max_seconds"
    printf -v "$result_variable" '%s' "$computed_timeout"
}

## A successful rndc retransfer only means BIND accepted the command. Poll all
## replicas as one pending set: a completed zone is removed immediately while
## queued zones keep their share of the same scaled deadline. This avoids the
## old N * timeout sequential wait and supports transfers completing in any
## order. Each argument is "<zone><TAB><primary-address>".
function named_wait_replicas_converged {
    local pair zone primary primary_serial replica_serial now start deadline
    local timeout pending_count
    local -a zone_order=()
    declare -A pending_primary=()
    declare -A primary_ok=()
    declare -A replica_ok=()
    declare -A last_primary_serial=()
    declare -A last_replica_serial=()

    (( $# > 0 )) || return 0
    if ! named_replica_convergence_timeout timeout "$@"
    then
        return 1
    fi

    for pair in "$@"
    do
        IFS=$'\t' read -r zone primary <<< "$pair"
        [[ -n $zone && -n $primary ]] || continue
        if [[ -z ${pending_primary[$zone]+present} ]]
        then
            zone_order+=("$zone")
        fi
        pending_primary["$zone"]="$primary"
        primary_ok["$zone"]=0
        replica_ok["$zone"]=0
    done

    pending_count="${#pending_primary[@]}"
    (( pending_count > 0 )) || return 0
    start="$(named_monotonic_seconds)"
    if [[ ! $start =~ ^[0-9]+$ ]]
    then
        err "Cannot determine named replica convergence deadline"
        return 1
    fi
    deadline=$(( start + timeout ))

    while (( pending_count > 0 ))
    do
        for zone in "${zone_order[@]}"
        do
            [[ -n ${pending_primary[$zone]+present} ]] || continue
            primary="${pending_primary[$zone]}"
            primary_serial=""
            replica_serial=""
            primary_ok["$zone"]=0
            replica_ok["$zone"]=0

            if named_query_soa_serial primary_serial "$primary" "$zone"
            then
                primary_ok["$zone"]=1
                last_primary_serial["$zone"]="$primary_serial"
            fi
            if named_query_soa_serial replica_serial 127.0.0.1 "$zone"
            then
                replica_ok["$zone"]=1
                last_replica_serial["$zone"]="$replica_serial"
            fi

            if [[ ${primary_ok[$zone]} == 1 && ${replica_ok[$zone]} == 1 && \
                  $primary_serial == "$replica_serial" ]]
            then
                unset 'pending_primary[$zone]'
                pending_count=$((pending_count - 1))
            fi
        done

        (( pending_count > 0 )) || return 0
        now="$(named_monotonic_seconds)"
        if [[ ! $now =~ ^[0-9]+$ || $now -ge $deadline ]]
        then
            break
        fi
        sleep 1
    done

    ## Report only zones that are still pending. Zones which converged in an
    ## earlier pass must not be made to look unhealthy by a later timeout.
    for zone in "${zone_order[@]}"
    do
        [[ -n ${pending_primary[$zone]+present} ]] || continue
        primary="${pending_primary[$zone]}"
        if [[ ${primary_ok[$zone]:-0} != 1 || ${replica_ok[$zone]:-0} != 1 ]]
        then
            err "Could not verify replica SOA for zone $zone against primary $primary"
        else
            err "Replica SOA did not converge for zone $zone (primary ${last_primary_serial[$zone]}, local ${last_replica_serial[$zone]})"
        fi
    done
    return 1
}

function restart_named {
    local conf zones type zone primary
    local failed=0
    local force_retransfer="${NAMED_FORCE_RETRANSFER:-true}"
    local -a verify_pairs=()
    conf="${1:-/var/named/srvctl.conf}"

    ## Validate the full include graph (including srvctl.conf) before a restart
    ## can take the currently working authoritative server down.
    if ! named-checkconf -z
    then
        err "named configuration preflight FAILED!"
        return 1
    fi

    ## Parse before restarting as an unreadable generated include should be a
    ## hard failure even if named-checkconf was stubbed or configured elsewhere.
    if ! zones="$(named_managed_zones "$conf")"
    then
        return 1
    fi

    if ! systemctl restart named.service
    then
        err "named restart FAILED!"
        systemctl status named.service --no-pager
        return 1
    fi

    if ! named_wait_rndc_ready
    then
        systemctl status named.service --no-pager
        return 1
    fi

    msg "restarted named.service"

    ## Issue every propagation command before waiting for individual replicas,
    ## so one slow transfer cannot prevent later zones from being attempted.
    while IFS=$'\t' read -r type zone primary
    do
        [[ -n $type && -n $zone ]] || continue

        case "$type" in
            master)
                if ! rndc notify "$zone"
                then
                    err "rndc notify FAILED for zone $zone"
                    failed=1
                fi
                ;;
            slave)
                if [[ -z $primary ]]
                then
                    err "Cannot determine primary address for replica zone $zone"
                    failed=1
                elif [[ $force_retransfer != true ]]
                then
                    if ! rndc refresh "$zone"
                    then
                        err "rndc refresh FAILED for zone $zone"
                        failed=1
                    fi
                elif ! rndc retransfer "$zone"
                then
                    err "rndc retransfer FAILED for zone $zone"
                    failed=1
                else
                    verify_pairs+=("$zone"$'\t'"$primary")
                fi
                ;;
        esac
    done <<< "$zones"

    if ! named_wait_replicas_converged "${verify_pairs[@]}"
    then
        failed=1
    fi

    return "$failed"
}
