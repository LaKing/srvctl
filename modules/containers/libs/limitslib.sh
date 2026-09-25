#!/bin/bash

##
##   containers/libs/limitslib.sh — per-container CPU and memory limits.
##
##   The datastore is the source of truth: the optional container fields
##   cpu_quota (e.g. 400%), memory_max and memory_high (e.g. 8G) override
##   the srvctl-nspawn@.service template's caps. apply_container_limits
##   renders them into the drop-in
##   /etc/systemd/system/srvctl-nspawn@C.service.d/50-srvctl-limits.conf
##   (removed again when no field is set) and pushes the effective values
##   into a running unit with 'systemctl set-property --runtime', so no
##   container restart is needed. The --runtime copy lives in /run and
##   always mirrors the drop-in, because both are written here.
##

## TEST SEAM for the selftest, not supported configuration.
: "${SC_LIMITS_UNIT_DIR:=/etc/systemd/system}"

## Must match the '## enforce limits' block of the template unit in
## create_srvctl_nspawn_service (libs/systemlib.sh).
SC_VE_DEFAULT_CPU_QUOTA=800%
SC_VE_DEFAULT_MEMORY_MAX=16G
SC_VE_DEFAULT_MEMORY_HIGH=8G

## Percent of one CPU, as systemd's CPUQuota= takes it.
function container_limits_valid_cpu { ## VAL
    [[ $1 =~ ^[1-9][0-9]{0,5}%$ ]]
}

## Whole bytes with a K/M/G/T suffix, as MemoryMax=/MemoryHigh= take it.
function container_limits_valid_memory { ## VAL
    [[ $1 =~ ^[1-9][0-9]{0,8}[KMGT]$ ]]
}

function container_limits_dropin { ## C
    printf '%s\n' "$SC_LIMITS_UNIT_DIR/srvctl-nspawn@$1.service.d/50-srvctl-limits.conf"
}

## Print "cpu_quota memory_max memory_high" from the datastore, '-' for unset.
function container_limits_fields { ## C
    local json
    json="$(out container "$1" json)" || return $?
    printf '%s' "$json" | /bin/node -e '
        const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
        const v = (k) => (r[k] === undefined || r[k] === "" ? "-" : String(r[k]));
        console.log(v("cpu_quota"), v("memory_max"), v("memory_high"));
    '
}

## Render the drop-in for the given field values; prints nothing when all
## fields are unset. Invalid stored values are refused, not rendered.
function container_limits_config { ## CPU MEMMAX MEMHIGH
    local cpu="$1" max="$2" high="$3" v
    if [[ $cpu != - ]] && ! container_limits_valid_cpu "$cpu"
    then
        err "Invalid cpu_quota: $cpu"; return 22
    fi
    for v in "$max" "$high"
    do
        if [[ $v != - ]] && ! container_limits_valid_memory "$v"
        then
            err "Invalid memory limit: $v"; return 22
        fi
    done
    [[ $cpu$max$high == --- ]] && return 0
    printf '%s\n' '# srvctl limits - generated from the datastore, do not edit' '[Service]'
    [[ $cpu == - ]] || printf 'CPUQuota=%s\n' "$cpu"
    [[ $max == - ]] || printf 'MemoryMax=%s\n' "$max"
    [[ $high == - ]] || printf 'MemoryHigh=%s\n' "$high"
}

## Reconcile one container's drop-in with the datastore. Returns 0 without
## touching systemd when the drop-in is already current.
function apply_container_limits { ## C
    local C="$1" fields cpu max high config file current=""
    fields="$(container_limits_fields "$C")" || return $?
    read -r cpu max high <<< "$fields"
    config="$(container_limits_config "$cpu" "$max" "$high")" || return $?
    file="$(container_limits_dropin "$C")"
    [[ -f $file ]] && current="$(cat "$file")"
    [[ $config == "$current" ]] && return 0

    if [[ -z $config ]]
    then
        msg "Reset $C resource limits to the defaults"
        rm -f "$file"
        rmdir --ignore-fail-on-non-empty "${file%/*}"
    else
        msg "Set $C resource limits: cpu $cpu, memory max $max, memory high $high"
        mkdir -p "${file%/*}"
        printf '%s\n' "$config" > "$file"
    fi
    run systemctl daemon-reload

    if systemctl -q is-active "srvctl-nspawn@$C.service"
    then
        [[ $cpu == - ]] && cpu="$SC_VE_DEFAULT_CPU_QUOTA"
        [[ $max == - ]] && max="$SC_VE_DEFAULT_MEMORY_MAX"
        [[ $high == - ]] && high="$SC_VE_DEFAULT_MEMORY_HIGH"
        run systemctl set-property --runtime "srvctl-nspawn@$C.service" \
            "CPUQuota=$cpu" "MemoryMax=$max" "MemoryHigh=$high"
    fi
}

## Reconcile every container hosted here (called from the regenerate hook,
## so limits set on another host of the cluster follow the container).
function apply_all_container_limits {
    local container_list C rc=0
    container_list="$(get cluster container_list)" || return $?
    for C in $container_list
    do
        [[ -d /srv/$C/rootfs ]] || continue
        apply_container_limits "$C" || rc=$?
    done
    return $rc
}
