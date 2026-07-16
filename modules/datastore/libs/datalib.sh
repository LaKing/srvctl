#!/bin/bash

##
##   modules/datastore/libs/datalib.sh — datastore initialization and
##   cluster data synchronization helpers.
##
##   publish_data synchronizes static /etc/srvctl/data and publishes the
##   canonical /etc/srvctl/clusters.json to every host in that topology using
##   a validate/stage/commit/verify transaction. grab_data is intentionally
##   static-data-only; grab_cluster_config is the explicit, staged topology
##   import path. These helpers are usable via exec-function.
##   init_datastore_install (root only) creates the RO/RW
##   directories, seeds hosts/containers/users json and git-inits the RW
##   directory. init_datastore, called from hooks/init.sh, picks the RO or
##   RW directory, seeds missing files and exports SC_DATASTORE_DIR for
##   main.mjs / lib.js.
##

## sc exec-function publish_data

function _srvctl_cluster_cli() {
    /bin/node "$SC_INSTALL_DIR/modules/containers/lib/cluster-config-cli.js" "$@"
}

function _cluster_config_require_root() {
    [[ $UID -eq 0 ]]
}

function _cluster_publication_state_dir() {
    printf '%s\n' "${SC_CLUSTER_PUBLICATION_STATE_DIR:-/var/srvctl3/cluster-config/publication}"
}

function _cluster_publication_manifest_path() {
    printf '%s/publication-inventory.v1\n' "$(_cluster_publication_state_dir)"
}

function _cluster_retirement_receipt_path() {
    printf '%s/retired/%s.sha256\n' "$(_cluster_publication_state_dir)" "$1"
}

function _cluster_atomic_state_file() {
    local destination="$1" content="$2" parent temporary
    parent="${destination%/*}"
    [[ $parent == "$destination" ]] && parent=.
    if [[ -L $parent ]] || [[ -L $destination ]]
    then
        return 113
    fi
    mkdir -p -- "$parent" || return 113
    chmod 700 -- "$parent" || return 113
    temporary="$(mktemp "$parent/.srvctl-state.XXXXXX")" || return 113
    if ! printf '%s' "$content" > "$temporary" ||
       ! chmod 600 -- "$temporary" ||
       ! mv -- "$temporary" "$destination"
    then
        rm -f -- "$temporary"
        return 113
    fi
}

## Print a validated normalized manifest as sha256<TAB>HASH followed by
## host<TAB>HOSTNAME lines. This stores inventory only, never topology fields.
function _cluster_load_publication_manifest() {
    local manifest type value extra
    local version_seen=0 sha_seen=0 sha=""
    local -a hosts=()
    local -A seen=()
    manifest="$(_cluster_publication_manifest_path)"

    [[ -e $manifest ]] || return 100
    if [[ -L $manifest ]] || [[ ! -f $manifest ]]
    then
        err "Invalid cluster publication manifest: $manifest"
        return 113
    fi
    ## Atomic writers always terminate every record. A truncated final host
    ## line must not disappear from the prior inventory merely because bash's
    ## read loop did not receive its delimiter.
    if [[ ! -s $manifest ]] ||
       [[ $(tail -c 1 -- "$manifest" | wc -l) -ne 1 ]]
    then
        return 113
    fi
    while IFS=$'\t' read -r type value extra
    do
        [[ -z $extra ]] || return 113
        case "$type" in
            version)
                [[ $version_seen -eq 0 && $value == 1 ]] || return 113
                version_seen=1
                ;;
            sha256)
                [[ $sha_seen -eq 0 && $value =~ ^[0-9a-f]{64}$ ]] || return 113
                sha="$value"
                sha_seen=1
                ;;
            host)
                [[ $value =~ ^[a-z0-9][a-z0-9.-]{0,252}$ ]] || return 113
                [[ $value != *..* && ! -v seen["$value"] ]] || return 113
                hosts+=("$value")
                seen["$value"]=1
                ;;
            *)
                return 113
                ;;
        esac
    done < "$manifest"
    [[ $version_seen -eq 1 && $sha_seen -eq 1 ]] || return 113

    printf 'sha256\t%s\n' "$sha"
    for value in "${hosts[@]}"
    do
        printf 'host\t%s\n' "$value"
    done
}

## Compare a caller's stable, already-validated canonical snapshot with the
## last successful fleet publication. This is read-only so orchestration such
## as regenerate_all_hosts can fail before contacting or mutating any host.
## Return 1 for a valid but different inventory and preserve manifest data
## errors (100 absent, 113 invalid) for callers that need the distinction.
function verify_cluster_publication_inventory() { ## sha256 [ordered-host ...]
    local current_sha="${1:-}" manifest_output record_type record_value manifest_sha=""
    local host index
    local -a current_hosts=() manifest_hosts=()
    local -A seen=()
    shift || return 113

    [[ $current_sha =~ ^[0-9a-f]{64}$ ]] || return 113
    for host in "$@"
    do
        [[ $host =~ ^[a-z0-9][a-z0-9.-]{0,252}$ && $host != *..* ]] || return 113
        [[ ! -v seen["$host"] ]] || return 113
        seen["$host"]=1
        current_hosts+=("$host")
    done

    manifest_output="$(_cluster_load_publication_manifest)" || return $?
    while IFS=$'\t' read -r record_type record_value
    do
        case "$record_type" in
            sha256) manifest_sha="$record_value" ;;
            host) manifest_hosts+=("$record_value") ;;
            *) return 113 ;;
        esac
    done <<< "$manifest_output"

    [[ $manifest_sha == "$current_sha" ]] || return 1
    [[ ${#manifest_hosts[@]} -eq ${#current_hosts[@]} ]] || return 1
    for index in "${!current_hosts[@]}"
    do
        [[ ${manifest_hosts[$index]} == "${current_hosts[$index]}" ]] || return 1
    done
    return 0
}

function _cluster_store_publication_manifest() {
    local sha="$1" host content=$'version\t1\n'
    shift
    local -A seen=()
    [[ $sha =~ ^[0-9a-f]{64}$ ]] || return 113
    content+="sha256"$'\t'"$sha"$'\n'
    for host in "$@"
    do
        [[ $host =~ ^[a-z0-9][a-z0-9.-]{0,252}$ ]] || return 113
        [[ $host != *..* && ! -v seen["$host"] ]] || return 113
        seen["$host"]=1
        content+="host"$'\t'"$host"$'\n'
    done
    _cluster_atomic_state_file "$(_cluster_publication_manifest_path)" "$content"
}

function _cluster_read_retirement_receipt() {
    local host="$1" receipt value extra
    receipt="$(_cluster_retirement_receipt_path "$host")"
    [[ -e $receipt ]] || return 100
    if [[ -L $receipt ]] || [[ ! -f $receipt ]]
    then
        return 113
    fi
    IFS=$'\t' read -r value extra < "$receipt" || return 113
    [[ $value =~ ^[0-9a-f]{64}$ && -z $extra ]] || return 113
    printf '%s\n' "$value"
}

function _cluster_store_retirement_receipt() {
    local host="$1" sha="$2"
    [[ $host =~ ^[a-z0-9][a-z0-9.-]{0,252}$ && $host != *..* ]] || return 113
    [[ $sha =~ ^[0-9a-f]{64}$ ]] || return 113
    _cluster_atomic_state_file "$(_cluster_retirement_receipt_path "$host")" "$sha"$'\n'
}

function _cluster_consume_retirement_receipt() {
    local host="$1" receipt
    receipt="$(_cluster_retirement_receipt_path "$host")"
    [[ ! -L $receipt ]] || return 113
    rm -f -- "$receipt"
}

function _cluster_remote_command() {
    local host="$1"
    shift
    ssh -n -o ConnectTimeout=3 -o BatchMode=yes "$host" "$@"
}

function _cluster_remote_bash() {
    local host="$1" script="$2" quoted
    printf -v quoted '%q' "$script"
    _cluster_remote_command "$host" "/bin/bash -c $quoted"
}

## Capability checks deliberately precede every rsync. A mixed-version fleet
## must fail without staging or changing a canonical topology anywhere.
function _cluster_remote_capability() {
    local host="$1" actual helper cli generator script capability
    helper="$SC_INSTALL_DIR/modules/containers/lib/cluster-config.sh"
    cli="$SC_INSTALL_DIR/modules/containers/lib/cluster-config-cli.js"
    generator="$SC_INSTALL_DIR/modules/containers/host-conf.js"

    actual="$(_cluster_remote_command "$host" hostname 2> /dev/null)" || return $?
    [[ $actual == "$host" ]] || return 1

    printf -v script 'test -x /bin/node && test -r %q && test -r %q && source %q && cluster_config_capability' \
        "$cli" "$generator" "$helper"
    capability="$(_cluster_remote_bash "$host" "$script")" || return $?
    [[ $capability == srvctl-cluster-config-v2 ]]
}

function _cluster_publish_static_to() {
    local host="$1" rsync_shell='ssh -o BatchMode=yes -o ConnectTimeout=3'
    _cluster_remote_command "$host" 'mkdir -p /etc/srvctl' &&
        rsync -avz -e "$rsync_shell" '--exclude=/data/clusters*.json' \
            /etc/srvctl/data "$host:/etc/srvctl"
}

function _cluster_stage_to() {
    local host="$1" canonical="$2" prepared="$3"
    local rsync_shell='ssh -o BatchMode=yes -o ConnectTimeout=3' script
    printf -v script 'rm -f -- %q && mkdir -p /etc/srvctl' "$prepared"
    _cluster_remote_bash "$host" "$script" &&
        rsync -avz -e "$rsync_shell" "$canonical" "$host:$prepared"
}

function _cluster_validate_remote_prepared() {
    local host="$1" prepared="$2" expected_sha="$3"
    local helper script
    helper="$SC_INSTALL_DIR/modules/containers/lib/cluster-config.sh"
    # shellcheck disable=SC2016 # hostname expands in the remote bash
    printf -v script 'test "$(hostname)" = %q && source %q && validate_prepared_cluster_config %q %q' \
        "$host" "$helper" "$prepared" "$expected_sha"
    _cluster_remote_bash "$host" "$script"
}

function _cluster_apply_remote_prepared() {
    local host="$1" prepared="$2" expected_sha="$3"
    local helper script
    helper="$SC_INSTALL_DIR/modules/containers/lib/cluster-config.sh"
    # shellcheck disable=SC2016 # hostname expands in the remote bash
    printf -v script 'test "$(hostname)" = %q && source %q && apply_prepared_cluster_config %q %q' \
        "$host" "$helper" "$prepared" "$expected_sha"
    _cluster_remote_bash "$host" "$script"
}

function _cluster_remote_sha() {
    local host="$1" canonical="$2" cli script
    cli="$SC_INSTALL_DIR/modules/containers/lib/cluster-config-cli.js"
    printf -v script '/bin/node %q sha256 %q' "$cli" "$canonical"
    _cluster_remote_bash "$host" "$script"
}

function _cluster_verify_remote_projection() {
    local host="$1" canonical="$2" cli script
    cli="$SC_INSTALL_DIR/modules/containers/lib/cluster-config-cli.js"
    printf -v script '/bin/node %q verify %q /var/srvctl3/host/host.conf /var/srvctl3/host/hosts.json %q' \
        "$cli" "$canonical" "$host"
    _cluster_remote_bash "$host" "$script"
}

function _cluster_retire_remote() {
    local host="$1" expected_sha="$2" helper script
    helper="$SC_INSTALL_DIR/modules/containers/lib/cluster-config.sh"
    # shellcheck disable=SC2016 # hostname expands in the remote bash
    printf -v script 'test "$(hostname)" = %q && source %q && declare -F retire_cluster_config >/dev/null && retire_cluster_config %q' \
        "$host" "$helper" "$expected_sha"
    _cluster_remote_bash "$host" "$script"
}

function _cluster_remote_retirement_capability() {
    local host="$1" helper script capability
    helper="$SC_INSTALL_DIR/modules/containers/lib/cluster-config.sh"
    # shellcheck disable=SC2016 # command substitution expands remotely
    printf -v script 'source %q && test "$(cluster_config_capability)" = srvctl-cluster-config-v2 && declare -F retire_cluster_config >/dev/null && echo srvctl-cluster-retirement-v1' \
        "$helper"
    capability="$(_cluster_remote_bash "$host" "$script")" || return $?
    [[ $capability == srvctl-cluster-retirement-v1 ]]
}

function _cluster_quiesce_remote_retired_roles() {
    local host="$1" script
    ## named may keep serving an old authoritative generation after its config
    ## files disappear. Retirement therefore stops and disables it first; an
    ## absent unit is acceptable, an active/enabled unit afterward is not.
    script='systemctl disable --now named.service >/dev/null 2>&1 || true; ! systemctl is-active --quiet named.service && ! systemctl is-enabled --quiet named.service'
    _cluster_remote_bash "$host" "$script"
}

function _cluster_verify_remote_retired() {
    local host="$1" expected_sha="$2" script
    # shellcheck disable=SC2016 # files and command substitution are remote
    printf -v script 'test "$(hostname)" = %q && test ! -e /etc/srvctl/clusters.json && test ! -e /etc/srvctl/data/clusters.json && test ! -e /etc/srvctl/host.conf && test ! -e /etc/srvctl/hosts.json && test ! -e /var/srvctl3/host/host.conf && test ! -e /var/srvctl3/host/hosts.json && test "$(cat /var/srvctl3/cluster-config/retired-generation.sha256)" = %q && ! systemctl is-active --quiet named.service && ! systemctl is-enabled --quiet named.service' \
        "$host" "$expected_sha"
    _cluster_remote_bash "$host" "$script"
}

function _cluster_cleanup_remote_prepared() {
    local host="$1" prepared="$2" script
    printf -v script 'rm -f -- %q' "$prepared"
    _cluster_remote_bash "$host" "$script"
}

function _cluster_acquire_local_publication_lock() {
    local result_variable="$1"
    local lock_file="${SC_CLUSTER_CONFIG_LOCK_FILE:-/run/srvctl-cluster-config.lock}"
    local lock_parent lock_fd
    lock_parent="${lock_file%/*}"
    [[ $lock_parent == "$lock_file" ]] && lock_parent=.
    mkdir -p -- "$lock_parent" || return 113
    exec {lock_fd}>>"$lock_file" || return 113
    if ! flock --shared --wait 60 "$lock_fd"
    then
        exec {lock_fd}>&-
        return 113
    fi
    printf -v "$result_variable" '%s' "$lock_fd"
}

function _cluster_release_local_publication_lock() {
    local lock_fd="$1" rc=0
    flock --unlock "$lock_fd" || rc=113
    exec {lock_fd}>&-
    return "$rc"
}

## Serialize inventory-state transitions for the entire initialize, publish,
## and retire workflows. The canonical topology lock below protects local file
## reads/writes; this separate exclusive lock prevents a retire receipt check
## racing a publisher that could otherwise re-enroll the same host.
function _with_cluster_publication_workflow_lock() {
    local callback="$1"
    shift
    local lock_file="${SC_CLUSTER_PUBLICATION_LOCK_FILE:-/run/srvctl-cluster-publication.lock}"
    local lock_parent lock_fd rc
    lock_parent="${lock_file%/*}"
    [[ $lock_parent == "$lock_file" ]] && lock_parent=.
    mkdir -p -- "$lock_parent" || return 113
    exec {lock_fd}>>"$lock_file" || return 113
    chmod 644 -- "$lock_file" || { exec {lock_fd}>&-; return 113; }
    if ! flock --wait 60 "$lock_fd"
    then
        exec {lock_fd}>&-
        return 113
    fi
    "$callback" "$@"
    rc=$?
    flock --unlock "$lock_fd"
    exec {lock_fd}>&-
    return "$rc"
}

function _cluster_local_capability() {
    local helper capability
    helper="$SC_INSTALL_DIR/modules/containers/lib/cluster-config.sh"
    if ! declare -F cluster_config_capability > /dev/null ||
       ! declare -F apply_prepared_cluster_config > /dev/null
    then
        # shellcheck source=/dev/null
        source "$helper" || return $?
    fi
    capability="$(cluster_config_capability)" || return $?
    [[ $capability == srvctl-cluster-config-v2 ]]
}

function _cluster_apply_local_prepared() {
    apply_prepared_cluster_config "$1" "$2"
}

function _cluster_cleanup_prepared_fleet() {
    local prepared="$1" host
    shift
    local failed=0
    for host in "$@"
    do
        if ! _cluster_cleanup_remote_prepared "$host" "$prepared"
        then
            err "Cannot clean prepared cluster topology from $host: $prepared"
            failed=1
        fi
    done
    return "$failed"
}

## One-time upgrade acknowledgement. It records only the exact canonical SHA
## and ordered hostnames after proving every listed host already serves that
## generation and its matching projections. It cannot discover a host that an
## operator removed before creating the first manifest, hence the explicit
## confirmation phrase.
function _initialize_cluster_publication_workflow() { ## confirm-complete-inventory
    local confirmation="${1:-}" canonical=/etc/srvctl/clusters.json
    local expected_sha host_output host local_host="${HOSTNAME:-$(hostname)}"
    local manifest_status failed=0 remote_sha projection_sha final_sha publication_lock_fd
    local -a all_hosts=() remote_hosts=()
    local -A seen=()

    if ! _cluster_config_require_root
    then
        err "Initializing cluster publication requires root"
        return 1
    fi
    if [[ $confirmation != confirm-complete-inventory ]]
    then
        err "Refusing publication baseline without: confirm-complete-inventory"
        return 1
    fi
    if _cluster_load_publication_manifest > /dev/null
    then
        err "Cluster publication manifest is already initialized"
        return 1
    else
        manifest_status=$?
    fi
    if [[ $manifest_status -ne 100 ]]
    then
        err "Cluster publication manifest is invalid and cannot be replaced"
        return 1
    fi

    expected_sha="$(_srvctl_cluster_cli sha256 "$canonical")" || {
        err "Cannot validate canonical cluster topology $canonical"
        return 1
    }
    host_output="$(_srvctl_cluster_cli hosts "$canonical")" || return 1
    while IFS= read -r host
    do
        [[ -n $host ]] || continue
        if [[ ! -v seen["$host"] ]]
        then
            all_hosts+=("$host")
            seen["$host"]=1
            [[ $host == "$local_host" ]] || remote_hosts+=("$host")
        fi
    done <<< "$host_output"
    if ! _srvctl_cluster_cli verify "$canonical" \
        /var/srvctl3/host/host.conf /var/srvctl3/host/hosts.json "$local_host" > /dev/null
    then
        err "Local cluster topology projection is not current on $local_host"
        return 1
    fi

    for host in "${remote_hosts[@]}"
    do
        if ! _cluster_remote_capability "$host"
        then
            err "Cluster publication initialization capability failed for $host"
            failed=1
            continue
        fi
        remote_sha="$(_cluster_remote_sha "$host" "$canonical")" || remote_sha=""
        projection_sha="$(_cluster_verify_remote_projection "$host" "$canonical")" || projection_sha=""
        if [[ $remote_sha != "$expected_sha" || $projection_sha != "$expected_sha" ]]
        then
            err "Cluster publication initialization found topology drift on $host"
            failed=1
        fi
    done
    [[ $failed -eq 0 ]] || return 1

    if ! _cluster_acquire_local_publication_lock publication_lock_fd
    then
        err "Cannot lock canonical topology while initializing publication"
        return 1
    fi
    final_sha="$(_srvctl_cluster_cli sha256 "$canonical")" || final_sha=""
    if [[ $final_sha != "$expected_sha" ]] ||
       ! _srvctl_cluster_cli verify "$canonical" \
            /var/srvctl3/host/host.conf /var/srvctl3/host/hosts.json "$local_host" > /dev/null
    then
        _cluster_release_local_publication_lock "$publication_lock_fd" || true
        err "Canonical topology changed during publication initialization"
        return 1
    fi
    if ! _cluster_store_publication_manifest "$expected_sha" "${all_hosts[@]}"
    then
        _cluster_release_local_publication_lock "$publication_lock_fd" || true
        err "Cannot write cluster publication manifest"
        return 1
    fi
    if ! _cluster_release_local_publication_lock "$publication_lock_fd"
    then
        err "Cannot release publication initialization lock"
        return 1
    fi
    msg "Initialized cluster publication inventory $expected_sha for ${#all_hosts[@]} hosts"
    return 0
}

## Explicitly detach one old host from the exact last-published generation.
## Workloads/services must already be drained by the operator; the confirmation
## phrase makes that responsibility deliberate. The host must still answer its
## old configured hostname, which makes rename ordering unambiguous.
function _retire_cluster_host_workflow() { ## hostname confirm-decommissioned
    local host="${1:-}" confirmation="${2:-}"
    local manifest_output expected_sha record_type record_value
    local receipt_sha receipt_status remote_sha projection_sha retire_sha
    local local_host="${HOSTNAME:-$(hostname)}" found=false

    if ! _cluster_config_require_root
    then
        err "Retiring a cluster host requires root"
        return 1
    fi
    if [[ -z $host || $confirmation != confirm-decommissioned ]]
    then
        err "Usage: retire_cluster_host HOST confirm-decommissioned"
        return 1
    fi
    if [[ $host == "$local_host" ]]
    then
        err "Retire $host from another cluster controller"
        return 1
    fi
    manifest_output="$(_cluster_load_publication_manifest)" || {
        err "Cannot retire a host without a valid publication manifest"
        return 1
    }
    while IFS=$'\t' read -r record_type record_value
    do
        case "$record_type" in
            sha256) expected_sha="$record_value" ;;
            host) [[ $record_value == "$host" ]] && found=true ;;
        esac
    done <<< "$manifest_output"
    if [[ $found != true || ! $expected_sha =~ ^[0-9a-f]{64}$ ]]
    then
        err "Host $host is not in the last-published cluster inventory"
        return 1
    fi

    if ! _cluster_remote_capability "$host"
    then
        err "Retirement capability/hostname preflight failed for $host"
        return 1
    fi
    if ! _cluster_remote_retirement_capability "$host"
    then
        err "Host $host lacks safe cluster retirement capability"
        return 1
    fi
    receipt_sha="$(_cluster_read_retirement_receipt "$host")"
    receipt_status=$?
    if [[ $receipt_status -eq 0 ]]
    then
        if [[ $receipt_sha != "$expected_sha" ]] ||
           ! _cluster_verify_remote_retired "$host" "$expected_sha"
        then
            err "Existing retirement receipt for $host cannot be verified"
            return 1
        fi
        msg "Host $host is already retired from generation $expected_sha"
        return 0
    elif [[ $receipt_status -ne 100 ]]
    then
        err "Invalid retirement receipt for $host"
        return 1
    fi

    ## Remote commit may have succeeded just before local receipt creation
    ## failed. Its locked SHA marker plus absent topology is sufficient proof
    ## to recreate the local receipt without requiring the live files again.
    if _cluster_verify_remote_retired "$host" "$expected_sha"
    then
        if ! _cluster_store_retirement_receipt "$host" "$expected_sha"
        then
            err "Cannot recreate retirement receipt for $host"
            return 1
        fi
        msg "Recovered retirement receipt for $host generation $expected_sha"
        return 0
    fi

    remote_sha="$(_cluster_remote_sha "$host" /etc/srvctl/clusters.json)" || remote_sha=""
    projection_sha="$(_cluster_verify_remote_projection "$host" /etc/srvctl/clusters.json)" || projection_sha=""
    if [[ $remote_sha != "$expected_sha" || $projection_sha != "$expected_sha" ]]
    then
        err "Host $host does not serve last-published generation $expected_sha"
        return 1
    fi
    if ! _cluster_quiesce_remote_retired_roles "$host"
    then
        err "Cannot stop/disable authoritative DNS role on $host"
        return 1
    fi
    retire_sha="$(_cluster_retire_remote "$host" "$expected_sha")" || {
        err "Locked topology retirement failed on $host"
        return 1
    }
    if [[ $retire_sha != "$expected_sha" ]] ||
       ! _cluster_verify_remote_retired "$host" "$expected_sha"
    then
        err "Cannot verify topology retirement on $host"
        return 1
    fi
    if ! _cluster_store_retirement_receipt "$host" "$expected_sha"
    then
        err "Host $host retired remotely, but local receipt creation failed; retry the same command"
        return 1
    fi
    msg "Retired host $host from cluster generation $expected_sha"
    return 0
}

function _publish_data_workflow() {
    local canonical=/etc/srvctl/clusters.json
    local host_output expected_sha local_sha host prepared_sha publication_lock_fd
    local manifest_output manifest_sha record_type record_value receipt_sha receipt_status
    local local_host="${HOSTNAME:-$(hostname)}"
    local failed=0 commit_succeeded=0 canonical_match_count=0
    local -a all_hosts=() remote_hosts=() prepared_hosts=() previous_hosts=() removed_hosts=()
    local -a commit_failed=() verify_failed=()
    local -A seen_hosts=()

    if ! _cluster_config_require_root
    then
        err "Publishing cluster topology requires root"
        return 1
    fi
    if ! expected_sha="$(_srvctl_cluster_cli sha256 "$canonical")" ||
       [[ ! $expected_sha =~ ^[0-9a-f]{64}$ ]]
    then
        err "Cannot validate canonical cluster topology $canonical"
        return 1
    fi
    if ! host_output="$(_srvctl_cluster_cli hosts "$canonical")"
    then
        err "Cannot enumerate the canonical cluster topology"
        return 1
    fi
    while IFS= read -r host
    do
        [[ -n $host ]] || continue
        if [[ ! -v seen_hosts["$host"] ]]
        then
            all_hosts+=("$host")
            seen_hosts["$host"]=1
            [[ $host == "$local_host" ]] || remote_hosts+=("$host")
        fi
    done <<< "$host_output"

    ## The caller is the already-canonical source. Verify its projection
    ## directly, but never require root SSH-to-self or stage/commit it.
    if ! _srvctl_cluster_cli verify "$canonical" \
        /var/srvctl3/host/host.conf /var/srvctl3/host/hosts.json "$local_host" > /dev/null
    then
        err "Local cluster topology projection is not current on $local_host"
        return 1
    fi

    ## Never let a host silently disappear from the deployment target set.
    ## The manifest contains only the prior SHA and ordered hostnames; removal
    ## requires an exact-generation retirement receipt created after the old
    ## host detached its live topology and projections.
    manifest_output="$(_cluster_load_publication_manifest)"
    receipt_status=$?
    if [[ $receipt_status -ne 0 ]]
    then
        if [[ $receipt_status -eq 100 ]]
        then
            err "Cluster publication is not initialized; run initialize_cluster_publication confirm-complete-inventory"
        else
            err "Cluster publication manifest is invalid"
        fi
        return 1
    fi
    while IFS=$'\t' read -r record_type record_value
    do
        case "$record_type" in
            sha256) manifest_sha="$record_value" ;;
            host) previous_hosts+=("$record_value") ;;
            *) err "Invalid normalized cluster publication manifest"; return 1 ;;
        esac
    done <<< "$manifest_output"
    [[ $manifest_sha =~ ^[0-9a-f]{64}$ ]] || return 1

    for host in "${all_hosts[@]}"
    do
        receipt_sha="$(_cluster_read_retirement_receipt "$host")"
        receipt_status=$?
        if [[ $receipt_status -eq 0 ]]
        then
            err "Retired host $host is still present in canonical topology; remove or rename it before publication"
            failed=1
        elif [[ $receipt_status -ne 100 ]]
        then
            err "Invalid retirement receipt for $host"
            failed=1
        fi
    done
    for host in "${previous_hosts[@]}"
    do
        if [[ ! -v seen_hosts["$host"] ]]
        then
            removed_hosts+=("$host")
            receipt_sha="$(_cluster_read_retirement_receipt "$host")"
            receipt_status=$?
            if [[ $receipt_status -ne 0 || $receipt_sha != "$manifest_sha" ]]
            then
                err "Host $host was removed without retiring deployed generation $manifest_sha"
                failed=1
            fi
        fi
    done
    [[ $failed -eq 0 ]] || return 1

    ## Phase 0: every remote must identify as the configured hostname and
    ## expose the exact v1 prepare/apply contract before any mutation.
    for host in "${remote_hosts[@]}"
    do
        if ! _cluster_remote_capability "$host"
        then
            err "Cluster topology capability preflight failed for $host"
            failed=1
        fi
    done
    [[ $failed -eq 0 ]] || return 1

    ## Static seeds are not topology. Keep their historical sync behavior but
    ## explicitly exclude the old split-brain clusters.json pathname.
    for host in "${remote_hosts[@]}"
    do
        msg "publishing static srvctl data to $host"
        if ! _cluster_publish_static_to "$host"
        then
            err "Static srvctl data synchronization failed for $host"
            failed=1
        fi
    done
    [[ $failed -eq 0 ]] || return 1

    prepared="/etc/srvctl/.clusters.json.srvctl-prepared.${expected_sha}.$$"

    ## Phase 1a: copy to a non-live same-filesystem path on every target.
    for host in "${remote_hosts[@]}"
    do
        if _cluster_stage_to "$host" "$canonical" "$prepared"
        then
            prepared_hosts+=("$host")
        else
            err "Cannot stage cluster topology on $host"
            failed=1
        fi
    done

    ## Phase 1b: validate schema, SHA, local membership, projection ability,
    ## and legacy-path compatibility under the remote shared lock. No live
    ## topology has changed yet.
    for host in "${prepared_hosts[@]}"
    do
        prepared_sha="$(_cluster_validate_remote_prepared \
            "$host" "$prepared" "$expected_sha")" || {
                err "Prepared cluster topology validation failed on $host"
                failed=1
                continue
            }
        if [[ $prepared_sha != "$expected_sha" ]]
        then
            err "Prepared cluster topology SHA mismatch on $host"
            failed=1
        fi
    done

    if [[ $failed -ne 0 || ${#prepared_hosts[@]} -ne ${#remote_hosts[@]} ]]
    then
        _cluster_cleanup_prepared_fleet "$prepared" "${remote_hosts[@]}" || failed=1
        err "Cluster topology prepare failed; no canonical topology was committed"
        return 1
    fi

    ## Hold the shared cluster lock from the final source check through remote
    ## commit and verification. All srvctl topology writers take this lock
    ## exclusively, closing the local grab/reconcile race.
    if ! _cluster_acquire_local_publication_lock publication_lock_fd
    then
        _cluster_cleanup_prepared_fleet "$prepared" "${remote_hosts[@]}" || true
        err "Cannot lock canonical cluster topology for publication"
        return 1
    fi

    ## Close the local edit-during-prepare window before the first irreversible
    ## remote commit. A changed source invalidates every prepared SHA.
    local_sha="$(_srvctl_cluster_cli sha256 "$canonical")" || local_sha=""
    if [[ $local_sha != "$expected_sha" ]]
    then
        _cluster_cleanup_prepared_fleet "$prepared" "${remote_hosts[@]}" || true
        _cluster_release_local_publication_lock "$publication_lock_fd" || true
        err "Canonical cluster topology changed during prepare; no commit was attempted"
        return 1
    fi

    ## Phase 2: each host repeats the full audit under the shared lock before
    ## an atomic rename, regenerates host.conf/hosts.json and removes only a
    ## byte-identical legacy path. A distributed commit cannot be rolled back;
    ## continue after failures, verify everyone, and report any partial result.
    for host in "${remote_hosts[@]}"
    do
        if _cluster_apply_remote_prepared "$host" "$prepared" "$expected_sha"
        then
            commit_succeeded=$((commit_succeeded + 1))
        else
            commit_failed+=("$host")
            err "Cluster topology commit failed on $host"
        fi
    done
    _cluster_cleanup_prepared_fleet "$prepared" "${remote_hosts[@]}" || failed=1

    local_sha="$(_srvctl_cluster_cli sha256 "$canonical")" || local_sha=""
    if [[ $local_sha != "$expected_sha" ]] ||
       ! _srvctl_cluster_cli verify "$canonical" \
            /var/srvctl3/host/host.conf /var/srvctl3/host/hosts.json "$local_host" > /dev/null
    then
        verify_failed+=("$local_host")
    fi
    for host in "${remote_hosts[@]}"
    do
        local_sha="$(_cluster_remote_sha "$host" "$canonical")" || local_sha=""
        [[ $local_sha == "$expected_sha" ]] && canonical_match_count=$((canonical_match_count + 1))
        prepared_sha="$(_cluster_verify_remote_projection "$host" "$canonical")" || prepared_sha=""
        if [[ $local_sha != "$expected_sha" || $prepared_sha != "$expected_sha" ]]
        then
            verify_failed+=("$host")
            err "Cluster topology verification failed on $host"
        fi
    done

    if [[ ${#commit_failed[@]} -eq 0 && ${#verify_failed[@]} -eq 0 && $failed -eq 0 ]]
    then
        if ! _cluster_store_publication_manifest "$expected_sha" "${all_hosts[@]}"
        then
            err "Cluster topology committed but publication manifest update failed"
            failed=1
        else
            for host in "${removed_hosts[@]}"
            do
                if ! _cluster_consume_retirement_receipt "$host"
                then
                    err "Cluster topology committed but retirement receipt cleanup failed for $host"
                    failed=1
                fi
            done
        fi
    fi

    if ! _cluster_release_local_publication_lock "$publication_lock_fd"
    then
        err "Cannot release local cluster topology publication lock"
        failed=1
    fi

    if [[ ${#commit_failed[@]} -ne 0 || ${#verify_failed[@]} -ne 0 || $failed -ne 0 ]]
    then
        if [[ $commit_succeeded -gt 0 || $canonical_match_count -gt 0 ]]
        then
            err "PARTIAL CLUSTER TOPOLOGY COMMIT: commit failures [${commit_failed[*]}], verification failures [${verify_failed[*]}]"
        else
            err "CLUSTER TOPOLOGY COMMIT FAILED: [${commit_failed[*]}], verification failures [${verify_failed[*]}]"
        fi
        return 1
    fi

    msg "Published cluster topology $expected_sha to ${#all_hosts[@]} hosts"
    return 0
}

function initialize_cluster_publication() {
    if ! _cluster_config_require_root
    then
        err "Initializing cluster publication requires root"
        return 1
    fi
    _with_cluster_publication_workflow_lock \
        _initialize_cluster_publication_workflow "$@"
}

function retire_cluster_host() {
    if ! _cluster_config_require_root
    then
        err "Retiring a cluster host requires root"
        return 1
    fi
    _with_cluster_publication_workflow_lock _retire_cluster_host_workflow "$@"
}

function publish_data() {
    if ! _cluster_config_require_root
    then
        err "Publishing cluster topology requires root"
        return 1
    fi
    _with_cluster_publication_workflow_lock _publish_data_workflow "$@"
}

function grab_data() { ## from-host
    ## Static seeds only. Topology import requires grab_cluster_config so an
    ## invalid or mixed-version source cannot leave stale host derivatives.

    local host
    local failed=0
    host="${1:-}"

    if ! _cluster_config_require_root
    then
        err "Importing static srvctl data requires root"
        return 1
    fi

    if [[ -n "$host" ]] &&
       [[ "$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 "$host" hostname 2> /dev/null)" == "$host" ]]
    then
        msg "syncing srvctl data from $host"
        if ! mkdir -p /etc/srvctl
        then
            err "Cannot prepare local /etc/srvctl"
            return 1
        fi
        if ! rsync -avz -e 'ssh -o BatchMode=yes -o ConnectTimeout=3' \
            '--exclude=/data/clusters*.json' \
            "$host:/etc/srvctl/data" /etc/srvctl
        then
            failed=1
        fi
        if [[ $failed -ne 0 ]]
        then
            err "rsync failed for $host"
        fi
    else
        err "Connection failed! $host"
        return 1
    fi

    return "$failed"
}

function grab_cluster_config() { ## from-host
    local host="${1:-}" canonical=/etc/srvctl/clusters.json
    local prepared expected_sha actual_sha
    local local_host="${HOSTNAME:-$(hostname)}"

    if ! _cluster_config_require_root
    then
        err "Importing cluster topology requires root"
        return 1
    fi
    if [[ -z $host ]] || ! _cluster_remote_capability "$host"
    then
        err "Cluster topology source capability failed: $host"
        return 1
    fi
    if ! _cluster_local_capability
    then
        err "Local cluster topology apply capability is unavailable"
        return 1
    fi

    prepared="/etc/srvctl/.clusters.json.srvctl-grab.$$"
    rm -f -- "$prepared" || return 1
    if ! rsync -avz -e 'ssh -o BatchMode=yes -o ConnectTimeout=3' \
        "$host:$canonical" "$prepared"
    then
        err "Cannot stage cluster topology from $host"
        rm -f -- "$prepared"
        return 1
    fi
    expected_sha="$(_srvctl_cluster_cli sha256 "$prepared")" || {
        err "Downloaded cluster topology from $host is invalid"
        rm -f -- "$prepared"
        return 1
    }
    if ! _cluster_apply_local_prepared "$prepared" "$expected_sha"
    then
        err "Cannot apply cluster topology downloaded from $host"
        rm -f -- "$prepared"
        return 1
    fi
    actual_sha="$(_srvctl_cluster_cli sha256 "$canonical")" || actual_sha=""
    if [[ $actual_sha != "$expected_sha" ]] ||
       ! _srvctl_cluster_cli verify "$canonical" \
            /var/srvctl3/host/host.conf /var/srvctl3/host/hosts.json "$local_host" > /dev/null
    then
        err "Applied cluster topology verification failed"
        return 1
    fi
    return 0
}

## one-time (root) datastore setup: directories, json seeds, git init, and
## the v4 monolithic -> file-per-entity conversion.
function init_datastore_install() {

    if [[ $USER != root ]]
    then
        return
    fi

    msg "init_datastore_install"

    ## srvctl3 database is static in /etc/srvctl/data, shared in the RW folder
    mkdir -p "$SC_DATASTORE_RO_DIR"
    mkdir -p "$SC_DATASTORE_RW_DIR"
    mkdir -p /etc/srvctl/data

    ## Fresh install: seed the v3 monolithic source files ONLY when the RW
    ## datastore has neither the per-entity dirs nor monolithic seeds yet.
    ## They are converted to file-per-entity by migrate_datastore_to_per_entity.
    if [[ ! -d "$SC_DATASTORE_RW_DIR/hosts" ]] && [[ ! -f "$SC_DATASTORE_RW_DIR/hosts.json" ]]
    then
        cat /var/srvctl3/host/hosts.json > "$SC_DATASTORE_RW_DIR/hosts.json"

        if [[ -f /etc/srvctl/data/containers.json ]]
        then
            cat /etc/srvctl/data/containers.json > "$SC_DATASTORE_RW_DIR/containers.json"
        else
            err "INITIALIZE-EMPTY srvctl data containers"
            echo '{}' > "$SC_DATASTORE_RW_DIR/containers.json"
        fi

        if [[ -f /etc/srvctl/data/users.json ]]
        then
            cat /etc/srvctl/data/users.json > "$SC_DATASTORE_RW_DIR/users.json"
        else
            ## seed table: root plus the single-letter resellers a-x
            err "INITIALIZE-DEFAULT srvctl data users"
            cat "$SC_INSTALL_DIR/modules/datastore/default-users.json" > "$SC_DATASTORE_RW_DIR/users.json"
        fi
    fi

    ## the RW datastore is a git repository; datastore_push commits into it
    if [[ ! -d $SC_DATASTORE_RW_DIR/.git ]]
    then
        msg "git init datastore"
        git init -q "$SC_DATASTORE_RW_DIR"
    fi

    ## Write .gitignore IDEMPOTENTLY (not only on fresh git init) so upgraded
    ## v3 repos also exclude secrets/keys and the migration backup. This is the
    ## second half of the "never commit secrets" guard (see gitlib.sh):
    ##   users/*/   — per-user key dirs (id_ecdsa, .password), keep *.json
    ##   cert/      — private keys
    ##   .monolithic-backup/ — the pre-migration archive
cat > "$SC_DATASTORE_RW_DIR/.gitignore" << EOF
.git.log
.gitignore
.monolithic-backup/
.per-entity
cert/
users/*/
EOF

    ## Guarantee the three entity type dirs exist so datastore_push's
    ## `git add -- hosts users containers` pathspec never errors on an empty
    ## type. per-entity user records live in users/<name>.json; the per-user
    ## key dirs used by ssh/codepad share users/ and coexist (store reads only
    ## *.json). cert/ is unchanged.
    mkdir -p "$SC_DATASTORE_RW_DIR/hosts"
    mkdir -p "$SC_DATASTORE_RW_DIR/users"
    mkdir -p "$SC_DATASTORE_RW_DIR/containers"
    mkdir -p "$SC_DATASTORE_RW_DIR/cert"

    migrate_datastore_to_per_entity
}

## Idempotent one-time conversion of the v3 monolithic RW datastore
## (hosts.json/users.json/containers.json) to the v4 file-per-entity layout
## (hosts/ users/ containers/). Skips once the monolithic files are archived.
function migrate_datastore_to_per_entity() {

    ## Already authoritative: nothing to do. The .per-entity marker (written
    ## below) means per-entity is the source of truth; the monolithic files may
    ## still sit on disk for a half-rsync'd old reader.
    [[ -f "$SC_DATASTORE_RW_DIR/.per-entity" ]] && return 0

    ## No monolithic source → nothing to migrate/consolidate.
    [[ -f "$SC_DATASTORE_RW_DIR/hosts.json" ]] || return 0

    msg "Migrating datastore to file-per-entity layout"

    ## migrate.mjs is write-if-absent + transactional: it CONSOLIDATES any
    ## monolithic records that are missing from per-entity WITHOUT clobbering
    ## existing per-entity records — safe on a half-migrated / split store, and
    ## safe to re-run.
    if run /bin/node "$SC_INSTALL_DIR/modules/datastore/lib/migrate.mjs" "$SC_DATASTORE_RW_DIR" "$SC_DATASTORE_RW_DIR"
    then
        ## Snapshot the pre-migration files, then mark per-entity AUTHORITATIVE.
        ## We deliberately do NOT delete the monolithic originals: a host that is
        ## only HALF rsync'd (new datalib.sh, still-old main.mjs/lib.js) must
        ## keep reading them. The .per-entity marker makes v4 readers ignore the
        ## monolithic (store.mjs) so deletes are honored once we are on v4; a
        ## later fully-v4 cleanup removes the stale originals.
        mkdir -p "$SC_DATASTORE_RW_DIR/.monolithic-backup"
        cp -f "$SC_DATASTORE_RW_DIR/hosts.json" "$SC_DATASTORE_RW_DIR/users.json" "$SC_DATASTORE_RW_DIR/containers.json" "$SC_DATASTORE_RW_DIR/.monolithic-backup/" 2> /dev/null
        : > "$SC_DATASTORE_RW_DIR/.per-entity"
        msg "Datastore migrated; per-entity is now authoritative (.per-entity marker set)"
        return 0
    fi

    ## migrate.mjs exited non-zero (e.g. a partial store — data loss). The
    ## transaction rolled back (no per-entity written) and the monolithic files
    ## are left in place. RETURN NON-ZERO so init_datastore aborts the command
    ## rather than operating on a broken/empty datastore. (err only prints; it
    ## does not set the exit status.)
    err "Datastore migration FAILED; monolithic files left in place — aborting"
    return 1
}

## select the RO or RW directory, ensure the per-entity layout, export vars
function init_datastore() {

    if $SC_DATASTORE_RO_USE
    then
        SC_DATASTORE_DIR="$SC_DATASTORE_RO_DIR"
        msg "Readonly datastore $SC_DATASTORE_RO_DIR"
    else
        SC_DATASTORE_DIR="$SC_DATASTORE_RW_DIR"
    fi

    ## Ensure the RW datastore is file-per-entity (fresh seed or one-time
    ## migration). Only when writable and root — never mutate the RO copy.
    ## Triggers when the per-entity dir is absent OR monolithic files remain
    ## (a not-yet / partially migrated store); init_datastore_install is
    ## idempotent and no-ops once fully migrated.
    if ! $SC_DATASTORE_RO_USE && [[ $USER == root ]]
    then
        ## Run install/migration when the per-entity layout is absent, OR when
        ## monolithic files remain and per-entity is NOT yet authoritative
        ## (no .per-entity marker) — i.e. a not-yet / partially migrated store.
        ## Once the marker is set the monolithic files may linger (kept for
        ## half-rsync'd old readers) without re-triggering.
        if [[ ! -d "$SC_DATASTORE_DIR/hosts" ]] || { [[ -f "$SC_DATASTORE_DIR/hosts.json" ]] && [[ ! -f "$SC_DATASTORE_DIR/.per-entity" ]]; }
        then
            ## init_datastore_install ends in migrate_datastore_to_per_entity;
            ## a migration failure (partial store / data loss) must STOP the
            ## command before it runs against a broken datastore. exif exits
            ## with the failing status if init_datastore_install returned != 0.
            init_datastore_install
            exif "datastore init/migration failed"
        fi

        ## Host membership and every static host field are owned by the sole
        ## canonical /etc/srvctl/clusters.json. Keep only runtime-owned fields
        ## (currently SSH host keys) in datastore host rows. The companion
        ## read-time overlay enforces the same rule for an unmodifiable RO
        ## fallback, so stale replica host_ip/hostnet values never win.
        if ! /bin/node "$SC_INSTALL_DIR/modules/datastore/lib/reconcile-hosts.mjs" \
            reconcile /etc/srvctl/clusters.json "$SC_DATASTORE_RW_DIR" \
            "${SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME:-${SC_HOSTNAME:-${HOSTNAME:-$(hostname)}}}" \
            > /dev/null
        then
            err "Datastore host topology reconciliation failed"
            return 1
        fi
    fi

    ## export for main.mjs: the datastore dir AND the effective readonly flag
    ## (v4 enforces readonly in the writer keyed on SC_DATASTORE_RO_USE).
    export SC_DATASTORE_DIR
    export SC_DATASTORE_RO_USE
}
