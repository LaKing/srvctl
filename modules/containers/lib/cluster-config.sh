#!/bin/bash

## Canonical cluster configuration orchestration. All mutating entry points use
## one lock shared by startup and fleet publication.

SC_CLUSTER_CONFIG_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
: "${SC_CLUSTER_CONFIG_LOCK_FILE:=/run/srvctl-cluster-config.lock}"
: "${SC_CLUSTER_CONFIG_ETC_ROOT:=/etc/srvctl}"
: "${SC_CLUSTER_CONFIG_VAR_ROOT:=/var/srvctl3}"
: "${SC_CLUSTER_CONFIG_LOCAL_ROOT:=/var/local/srvctl}"
: "${SC_CLUSTER_CONFIG_CLI:=$SC_CLUSTER_CONFIG_HELPER_DIR/cluster-config-cli.js}"
: "${SC_CLUSTER_CONFIG_GENERATOR:=$SC_CLUSTER_CONFIG_HELPER_DIR/../host-conf.js}"
: "${SC_CLUSTER_CONFIG_RETIRE_MARKER:=$SC_CLUSTER_CONFIG_VAR_ROOT/cluster-config/retired-generation.sha256}"
## The three variables below are TEST SEAMS for the sandboxed selftests, not
## supported configuration: production consumers (module conditions, datalib
## remote verification, vncproxy, diagnose) hardcode the /var/srvctl3/host
## and /etc/srvctl locations. Overriding them on a live host splits the
## projection across two places.
: "${SC_CLUSTER_CONFIG_HOST_DIR:=$SC_CLUSTER_CONFIG_VAR_ROOT/host}"
: "${SC_CLUSTER_CONFIG_LEGACY_HOST_CONF:=/etc/srvctl/host.conf}"
: "${SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE:=/etc/srvctl/hosts.json}"
: "${SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE:=$SC_CLUSTER_CONFIG_LOCAL_ROOT/modules.conf}"
: "${SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE:=/root/.srvctl/modules.conf}"

function cluster_config_capability() {
    echo "srvctl-cluster-config-v2"
}

function _cluster_config_cli() {
    local node_bin="${SC_CLUSTER_CONFIG_NODE:-/bin/node}"
    "$node_bin" "$SC_CLUSTER_CONFIG_CLI" "$@"
}

function _invalidate_cluster_config_caches() {
    rm -f -- "$SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE" \
        "$SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE"
}

function _read_cluster_retire_marker() {
    local marker="$SC_CLUSTER_CONFIG_RETIRE_MARKER" value
    if [[ -L $marker ]] || { [[ -e $marker ]] && [[ ! -f $marker ]]; }
    then
        echo "DATA-ERROR: invalid cluster retirement marker: $marker" >&2
        return 113
    fi
    [[ -f $marker ]] || return 100
    IFS= read -r value < "$marker" || return 113
    if [[ ! $value =~ ^[0-9a-f]{64}$ ]]
    then
        echo "DATA-ERROR: invalid cluster retirement marker content: $marker" >&2
        return 113
    fi
    echo "$value"
}

function _write_cluster_retire_marker() {
    local expected_sha="$1" marker="$SC_CLUSTER_CONFIG_RETIRE_MARKER"
    local parent temporary
    parent="${marker%/*}"
    [[ $parent == "$marker" ]] && parent=.
    mkdir -p -- "$parent" || return 113
    chmod 700 -- "$parent" || return 113
    temporary="$(mktemp "$parent/.retired-generation.XXXXXX")" || return 113
    if ! printf '%s\n' "$expected_sha" > "$temporary" ||
       ! chmod 600 -- "$temporary" ||
       ! mv -- "$temporary" "$marker"
    then
        rm -f -- "$temporary"
        return 113
    fi
}

## The projections live under $SC_CLUSTER_CONFIG_HOST_DIR; parents must exist
## and stay world-readable before the generator stages files beside them.
## Root later SOURCES host.conf from this directory, so a pre-existing entry
## is normalized, never trusted: a symlink or non-directory fails closed, a
## root caller re-asserts root ownership, and permissions are forced to 0755
## (a 0700 directory would lock out every non-root invocation; a writable one
## would let any user swap in their own projection).
function _ensure_cluster_host_dir() {
    local path parent
    for path in "$@"
    do
        parent="${path%/*}"
        [[ $parent == "$path" ]] && parent=.
        if [[ -L $parent ]] || { [[ -e $parent ]] && [[ ! -d $parent ]]; }
        then
            echo "DATA-ERROR: host projection directory is not a regular directory: $parent" >&2
            return 113
        fi
        mkdir -p -- "$parent" || return 113
        if [[ $EUID -eq 0 ]]
        then
            chown root:root -- "$parent" || return 113
        fi
        chmod 755 -- "$parent" || return 113
    done
}

## host.conf/hosts.json used to live in /etc/srvctl. A superseded copy there
## must never be sourced again, so every successful regeneration removes it.
## Callers that explicitly target the legacy path itself are left alone.
function _remove_legacy_host_projection() {
    local host_conf="$1" hosts_file="$2"
    [[ $SC_CLUSTER_CONFIG_LEGACY_HOST_CONF == "$host_conf" ]] || \
        rm -f -- "$SC_CLUSTER_CONFIG_LEGACY_HOST_CONF" || return 113
    [[ $SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE == "$hosts_file" ]] || \
        rm -f -- "$SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE" || return 113
    return 0
}

function _legacy_host_projection_present() {
    local host_conf="$1" hosts_file="$2"
    if [[ $SC_CLUSTER_CONFIG_LEGACY_HOST_CONF != "$host_conf" ]] && \
       [[ -e $SC_CLUSTER_CONFIG_LEGACY_HOST_CONF ]]
    then
        return 0
    fi
    if [[ $SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE != "$hosts_file" ]] && \
       [[ -e $SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE ]]
    then
        return 0
    fi
    return 1
}

## Cheap raw-byte generation probe for callers that already sourced the
## projection. cluster-config.js hashes the raw file bytes, so plain
## sha256sum is bit-compatible with the CLI sha256 and the SC_HOSTS_SHA256
## value embedded in host.conf. Used by init.sh to detect a publisher commit
## that landed after the cluster lock was released.
function cluster_generation_matches() {
    local expected_canonical="$1" expected_hosts="${2:-}"
    local canonical="${3:-/etc/srvctl/clusters.json}"
    local hosts_file="${4:-$SC_CLUSTER_CONFIG_HOST_DIR/hosts.json}"
    local sum
    sum="$(sha256sum -- "$canonical" 2>/dev/null)" || return 1
    [[ ${sum%% *} == "$expected_canonical" ]] || return 1
    if [[ -n $expected_hosts ]]
    then
        sum="$(sha256sum -- "$hosts_file" 2>/dev/null)" || return 1
        [[ ${sum%% *} == "$expected_hosts" ]] || return 1
    fi
    return 0
}

function audit_cluster_config_paths() {
    local canonical="${1:-/etc/srvctl/clusters.json}"
    local legacy="${2:-/etc/srvctl/data/clusters.json}"
    local etc_root="${3:-$SC_CLUSTER_CONFIG_ETC_ROOT}"
    local var_root="${4:-$SC_CLUSTER_CONFIG_VAR_ROOT}"
    local local_root="${5:-$SC_CLUSTER_CONFIG_LOCAL_ROOT}"
    local mode="${6:-full}"
    local root path found failed=false
    local -a roots exact_var_candidates

    exact_var_candidates=(
        "$var_root/clusters.json"
        "$var_root/datastore/clusters.json"
        "$var_root/gluster/srvctl-data/clusters.json"
    )
    for path in "${exact_var_candidates[@]}"
    do
        if [[ -e $path ]] || [[ -L $path ]]
        then
            echo "DATA-ERROR: unexpected clusters configuration: $path" >&2
            failed=true
        fi
    done

    roots=("$etc_root" "$local_root")
    [[ $mode == nonroot ]] || roots+=("$var_root")

    for root in "${roots[@]}"
    do
        [[ -d $root ]] || continue
        if [[ $root == "$var_root" ]]
        then
            ## These branches contain container operating systems, mounts, or
            ## bulk/user data and can hold millions of files. They are not
            ## srvctl configuration sources, so startup must never walk them.
            if ! found="$(find "$root" \
                \( -path "$root/rootfs" -o -path "$root/mounts" -o \
                   -path "$root/storage" -o -path "$root/nfs" -o \
                   -path "$root/share" -o -path "$root/gluster" \) -prune -o \
                -name clusters.json -print)"
            then
                echo "DATA-ERROR: cannot audit clusters configuration paths under $root" >&2
                return 113
            fi
        elif [[ $mode == nonroot ]]
        then
            ## Root performs the authoritative full audit while holding this
            ## same lock. Non-root callers inspect every traversable config
            ## directory but must not become unusable on CA/key directories
            ## they legitimately cannot enter.
            found="$(find "$root" -name clusters.json -print 2>/dev/null || true)"
        elif ! found="$(find "$root" -name clusters.json -print)"
        then
            echo "DATA-ERROR: cannot audit clusters configuration paths under $root" >&2
            return 113
        fi
        while IFS= read -r path
        do
            [[ -n $path ]] || continue
            if [[ $path == "$canonical" ]] || [[ $path == "$legacy" ]]
            then
                continue
            fi
            echo "DATA-ERROR: unexpected clusters configuration: $path" >&2
            failed=true
        done <<< "$found"
    done

    [[ $failed == false ]] || return 113
    return 0
}

function _validate_existing_cluster_files() {
    local path
    for path in "$@"
    do
        if [[ -L $path ]]
        then
            echo "DATA-ERROR: clusters configuration must not be a symlink: $path" >&2
            return 113
        fi
        [[ -e $path ]] || continue
        if [[ ! -f $path ]]
        then
            echo "DATA-ERROR: clusters configuration is not a regular file: $path" >&2
            return 113
        fi
        _cluster_config_cli validate "$path" >/dev/null || return $?
    done
}

## Validate every existing input before removing, renaming, or chmodding one.
function migrate_legacy_clusters_config() {
    local canonical="${1:-/etc/srvctl/clusters.json}"
    local legacy="${2:-/etc/srvctl/data/clusters.json}"
    local target_hostname="${3:-}"
    local canonical_device canonical_parent legacy_device path

    _validate_existing_cluster_files "$canonical" "$legacy" || return $?
    for path in "$canonical" "$legacy"
    do
        [[ ! -f $path ]] || {
            if [[ -n $target_hostname ]]
            then
                _cluster_config_cli local "$path" "$target_hostname" >/dev/null || return $?
            else
                _cluster_config_cli local "$path" >/dev/null || return $?
            fi
        }
    done

    if [[ -f $canonical ]] && [[ -f $legacy ]]
    then
        if ! cmp --silent -- "$canonical" "$legacy"
        then
            echo "DATA-ERROR: conflicting clusters configuration files:" >&2
            echo "  canonical: $canonical" >&2
            echo "  legacy:    $legacy" >&2
            echo "Merge the required topology into the canonical file, remove the legacy file, and retry." >&2
            return 113
        fi
        rm -- "$legacy" || return 113
    elif [[ -f $legacy ]]
    then
        canonical_parent="${canonical%/*}"
        [[ $canonical_parent == "$canonical" ]] && canonical_parent=.
        canonical_device="$(stat -c %d -- "$canonical_parent")" || return 113
        legacy_device="$(stat -c %d -- "$legacy")" || return 113
        if [[ $canonical_device != "$legacy_device" ]]
        then
            echo "DATA-ERROR: cannot atomically migrate clusters configuration across filesystems:" >&2
            echo "  canonical: $canonical" >&2
            echo "  legacy:    $legacy" >&2
            return 113
        fi
        mv -- "$legacy" "$canonical" || return 113
    fi

    [[ ! -f $canonical ]] || chmod 644 -- "$canonical" || return 113
    return 0
}

function refresh_cluster_host_config() {
    local canonical="${1:-/etc/srvctl/clusters.json}"
    local host_conf="${2:-$SC_CLUSTER_CONFIG_HOST_DIR/host.conf}"
    local hosts_file="${3:-$SC_CLUSTER_CONFIG_HOST_DIR/hosts.json}"
    local generator="${4:-$SC_CLUSTER_CONFIG_GENERATOR}"
    local node_bin="${5:-/bin/node}"
    local target_hostname="${6:-}"

    [[ -f $canonical ]] || return 0
    if [[ ! -x $node_bin ]] || [[ ! -f $generator ]]
    then
        echo "DATA-ERROR: cluster host configuration generator or Node.js is missing" >&2
        return 113
    fi
    _ensure_cluster_host_dir "$host_conf" "$hosts_file" || return $?
    if [[ -n $target_hostname ]]
    then
        "$node_bin" "$generator" "$canonical" "$host_conf" "$hosts_file" \
            "$target_hostname" || return $?
    else
        "$node_bin" "$generator" "$canonical" "$host_conf" "$hosts_file" || return $?
    fi
    chmod 644 -- "$host_conf" "$hosts_file" || return 113
    if [[ -n $target_hostname ]]
    then
        _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file" \
            "$target_hostname" >/dev/null || return $?
    else
        _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file" >/dev/null || return $?
    fi
}

function _with_cluster_config_lock() {
    local callback="$1"
    shift
    local lock_parent="${SC_CLUSTER_CONFIG_LOCK_FILE%/*}"
    local lock_fd rc
    [[ $lock_parent == "$SC_CLUSTER_CONFIG_LOCK_FILE" ]] && lock_parent=.
    mkdir -p -- "$lock_parent" || return 113
    exec {lock_fd}>>"$SC_CLUSTER_CONFIG_LOCK_FILE" || return 113
    chmod 644 -- "$SC_CLUSTER_CONFIG_LOCK_FILE" || { exec {lock_fd}>&-; return 113; }
    if ! flock --wait 60 "$lock_fd"
    then
        echo "DATA-ERROR: timed out waiting for cluster configuration lock" >&2
        exec {lock_fd}>&-
        return 113
    fi
    "$callback" "$@"
    rc=$?
    flock --unlock "$lock_fd"
    exec {lock_fd}>&-
    return "$rc"
}

function _reconcile_cluster_config_locked() {
    local canonical="$1" legacy="$2" host_conf="$3" hosts_file="$4"
    audit_cluster_config_paths "$canonical" "$legacy" || return $?
    migrate_legacy_clusters_config "$canonical" "$legacy" || return $?

    if [[ -f $canonical ]]
    then
        refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file" || return $?
        _remove_legacy_host_projection "$host_conf" "$hosts_file" || return $?
        _cluster_config_cli sha256 "$canonical" || return $?
    elif [[ -e $host_conf ]] || [[ -e $hosts_file ]] || \
         _legacy_host_projection_present "$host_conf" "$hosts_file"
    then
        echo "DATA-ERROR: canonical clusters configuration is absent but derived host configuration remains" >&2
        return 113
    else
        echo none
    fi
    return 0
}

function reconcile_cluster_config() {
    local canonical="${1:-/etc/srvctl/clusters.json}"
    local legacy="${2:-/etc/srvctl/data/clusters.json}"
    local host_conf="${3:-$SC_CLUSTER_CONFIG_HOST_DIR/host.conf}"
    local hosts_file="${4:-$SC_CLUSTER_CONFIG_HOST_DIR/hosts.json}"
    _with_cluster_config_lock _reconcile_cluster_config_locked \
        "$canonical" "$legacy" "$host_conf" "$hosts_file"
}

## The supported first-install flow starts while the kernel hostname is still
## localhost.localdomain. Validate the requested future hostname against the
## canonical topology and render its projections under the normal lock, but
## leave changing the live/persistent hostname to update-install.sh. init.sh
## deliberately does not source this future host.conf until after the reboot.
function _prepare_cluster_hostname_bootstrap_locked() {
    local target_hostname="$1" canonical="$2" legacy="$3"
    local host_conf="$4" hosts_file="$5"
    local bootstrap_sha marker_rc

    [[ -n $target_hostname ]] || {
        echo "DATA-ERROR: bootstrap hostname is required" >&2
        return 113
    }
    ## Hostname bootstrap is the explicit enrollment path used after a retired
    ## machine is assigned a new topology identity. Validate a pre-existing
    ## marker before mutating anything, and clear it only after the canonical
    ## file and both projections have been rendered successfully.
    _read_cluster_retire_marker >/dev/null
    marker_rc=$?
    if [[ $marker_rc -ne 0 && $marker_rc -ne 100 ]]
    then
        return "$marker_rc"
    fi
    audit_cluster_config_paths "$canonical" "$legacy" || return $?
    migrate_legacy_clusters_config "$canonical" "$legacy" \
        "$target_hostname" || return $?
    if [[ ! -f $canonical ]]
    then
        echo "DATA-ERROR: canonical clusters configuration is required for hostname bootstrap" >&2
        return 113
    fi
    refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file" \
        "$SC_CLUSTER_CONFIG_GENERATOR" "${SC_CLUSTER_CONFIG_NODE:-/bin/node}" \
        "$target_hostname" || return $?
    _remove_legacy_host_projection "$host_conf" "$hosts_file" || return $?
    bootstrap_sha="$(_cluster_config_cli sha256 "$canonical")" || return $?
    _invalidate_cluster_config_caches || return 113
    rm -f -- "$SC_CLUSTER_CONFIG_RETIRE_MARKER" || return 113
    echo "$bootstrap_sha"
}

function prepare_cluster_hostname_bootstrap() {
    local target_hostname="${1:-}"
    local canonical="${2:-/etc/srvctl/clusters.json}"
    local legacy="${3:-/etc/srvctl/data/clusters.json}"
    local host_conf="${4:-$SC_CLUSTER_CONFIG_HOST_DIR/host.conf}"
    local hosts_file="${5:-$SC_CLUSTER_CONFIG_HOST_DIR/hosts.json}"

    _with_cluster_config_lock _prepare_cluster_hostname_bootstrap_locked \
        "$target_hostname" "$canonical" "$legacy" "$host_conf" "$hosts_file"
}

function _verify_cluster_projection_unlocked() {
    local canonical="$1" legacy="$2" host_conf="$3" hosts_file="$4"
    audit_cluster_config_paths "$canonical" "$legacy" \
        "$SC_CLUSTER_CONFIG_ETC_ROOT" "$SC_CLUSTER_CONFIG_VAR_ROOT" \
        "$SC_CLUSTER_CONFIG_LOCAL_ROOT" nonroot || return $?
    if [[ -e $legacy ]]
    then
        echo "DATA-ERROR: legacy clusters configuration requires a root migration: $legacy" >&2
        return 113
    fi
    if _legacy_host_projection_present "$host_conf" "$hosts_file"
    then
        echo "DATA-ERROR: legacy host projection requires a root migration: $SC_CLUSTER_CONFIG_LEGACY_HOST_CONF" >&2
        return 113
    fi
    if [[ -f $canonical ]]
    then
        _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file"
        return $?
    fi
    if [[ -e $canonical ]] || [[ -e $host_conf ]] || [[ -e $hosts_file ]]
    then
        echo "DATA-ERROR: canonical clusters configuration is absent or invalid while derived files remain" >&2
        return 113
    fi
    echo none
    return 0
}

function verify_cluster_projection_nonroot() {
    local canonical="${1:-/etc/srvctl/clusters.json}"
    local legacy="${2:-/etc/srvctl/data/clusters.json}"
    local host_conf="${3:-$SC_CLUSTER_CONFIG_HOST_DIR/host.conf}"
    local hosts_file="${4:-$SC_CLUSTER_CONFIG_HOST_DIR/hosts.json}"
    local lock_fd rc

    if [[ -e $SC_CLUSTER_CONFIG_LOCK_FILE ]]
    then
        exec {lock_fd}<"$SC_CLUSTER_CONFIG_LOCK_FILE" || return 113
        flock --shared --wait 60 "$lock_fd" || { exec {lock_fd}>&-; return 113; }
        _verify_cluster_projection_unlocked "$canonical" "$legacy" "$host_conf" "$hosts_file"
        rc=$?
        flock --unlock "$lock_fd"
        exec {lock_fd}>&-
        return "$rc"
    fi
    if [[ -e $canonical ]] || [[ -e $legacy ]] || [[ -e $host_conf ]] || [[ -e $hosts_file ]] || \
       _legacy_host_projection_present "$host_conf" "$hosts_file"
    then
        echo "DATA-ERROR: cluster configuration lock is absent; a root reconciliation is required" >&2
        return 113
    fi
    _verify_cluster_projection_unlocked "$canonical" "$legacy" "$host_conf" "$hosts_file"
}

function _validate_prepared_cluster_config_locked() {
    local prepared="$1" expected_sha="$2" canonical="$3" legacy="$4"
    local host_conf="$5" hosts_file="$6"
    local actual_sha canonical_parent prepared_device canonical_device legacy_device

    if [[ -L $SC_CLUSTER_CONFIG_RETIRE_MARKER ]] ||
       { [[ -e $SC_CLUSTER_CONFIG_RETIRE_MARKER ]] && [[ ! -f $SC_CLUSTER_CONFIG_RETIRE_MARKER ]]; }
    then
        echo "DATA-ERROR: invalid cluster retirement marker: $SC_CLUSTER_CONFIG_RETIRE_MARKER" >&2
        return 113
    fi
    if [[ -f $SC_CLUSTER_CONFIG_RETIRE_MARKER ]]
    then
        _read_cluster_retire_marker >/dev/null || return $?
    fi

    audit_cluster_config_paths "$canonical" "$legacy" || return $?
    _validate_existing_cluster_files "$prepared" "$canonical" "$legacy" || return $?
    actual_sha="$(_cluster_config_cli sha256 "$prepared")" || return $?
    if [[ ! $expected_sha =~ ^[0-9a-f]{64}$ ]] || [[ $actual_sha != "$expected_sha" ]]
    then
        echo "DATA-ERROR: prepared clusters SHA-256 mismatch: expected $expected_sha, got $actual_sha" >&2
        return 113
    fi
    _cluster_config_cli local "$prepared" >/dev/null || return $?

    if [[ -f $legacy ]]
    then
        if [[ -f $canonical ]]
        then
            if ! cmp --silent -- "$legacy" "$canonical"
            then
                echo "DATA-ERROR: legacy clusters configuration diverges from the canonical file: $legacy" >&2
                return 113
            fi
        elif ! cmp --silent -- "$legacy" "$prepared"
        then
            echo "DATA-ERROR: legacy-only clusters configuration diverges from the prepared file: $legacy" >&2
            return 113
        fi
    fi

    canonical_parent="${canonical%/*}"
    [[ $canonical_parent == "$canonical" ]] && canonical_parent=.
    canonical_device="$(stat -c %d -- "$canonical_parent")" || return 113
    prepared_device="$(stat -c %d -- "$prepared")" || return 113
    if [[ $canonical_device != "$prepared_device" ]]
    then
        echo "DATA-ERROR: prepared clusters file must share the canonical filesystem: $prepared" >&2
        return 113
    fi
    if [[ ! -f $canonical ]] && [[ -f $legacy ]]
    then
        legacy_device="$(stat -c %d -- "$legacy")" || return 113
        if [[ $canonical_device != "$legacy_device" ]]
        then
            echo "DATA-ERROR: legacy-only clusters file cannot be atomically promoted across filesystems: $legacy" >&2
            return 113
        fi
    fi

    ## Arguments are part of the stable interface even though validation only
    ## needs their locations during the apply/render phase.
    [[ -n $host_conf && -n $hosts_file ]] || return 113
    echo "$actual_sha"
}

function validate_prepared_cluster_config() {
    local prepared="$1" expected_sha="$2"
    local canonical="${3:-/etc/srvctl/clusters.json}"
    local legacy="${4:-/etc/srvctl/data/clusters.json}"
    local host_conf="${5:-$SC_CLUSTER_CONFIG_HOST_DIR/host.conf}"
    local hosts_file="${6:-$SC_CLUSTER_CONFIG_HOST_DIR/hosts.json}"
    _with_cluster_config_lock _validate_prepared_cluster_config_locked \
        "$prepared" "$expected_sha" "$canonical" "$legacy" "$host_conf" "$hosts_file"
}

function _apply_prepared_cluster_config_locked() {
    local prepared="$1" expected_sha="$2" canonical="$3" legacy="$4"
    local host_conf="$5" hosts_file="$6"
    local temporary_host_conf temporary_hosts rc=0 legacy_only=false

    _validate_prepared_cluster_config_locked "$prepared" "$expected_sha" \
        "$canonical" "$legacy" "$host_conf" "$hosts_file" >/dev/null || return $?
    [[ ! -f $canonical && -f $legacy ]] && legacy_only=true

    temporary_host_conf="${host_conf}.prepared.$$.$RANDOM"
    temporary_hosts="${hosts_file}.prepared.$$.$RANDOM"
    _ensure_cluster_host_dir "$host_conf" "$hosts_file" || return $?
    /bin/node "$SC_CLUSTER_CONFIG_GENERATOR" \
        "$prepared" "$temporary_host_conf" "$temporary_hosts" || rc=$?
    if [[ $rc -eq 0 ]]
    then
        _cluster_config_cli verify "$prepared" "$temporary_host_conf" "$temporary_hosts" >/dev/null || rc=$?
    fi
    if [[ $rc -eq 0 ]]
    then
        ## The preflight proved this is only a redundant old pathname. Remove
        ## it before replacing canonical so a crash can never leave old legacy
        ## bytes disagreeing with the newly committed generation.
        if [[ $legacy_only == true ]]
        then
            mv -- "$legacy" "$canonical" || rc=113
            [[ $rc -ne 0 ]] || rm -f -- "$prepared" || rc=113
        else
            [[ ! -f $legacy ]] || rm -- "$legacy" || rc=113
        fi
    fi
    if [[ $rc -eq 0 ]] && [[ $legacy_only == false ]]
    then
        mv -- "$prepared" "$canonical" || rc=113
    fi
    if [[ $rc -eq 0 ]]
    then
        mv -- "$temporary_host_conf" "$host_conf" || rc=113
    fi
    if [[ $rc -eq 0 ]]
    then
        mv -- "$temporary_hosts" "$hosts_file" || rc=113
    fi
    if [[ $rc -eq 0 ]]
    then
        chmod 644 -- "$canonical" "$host_conf" "$hosts_file" || rc=113
    fi
    if [[ $rc -eq 0 ]]
    then
        _remove_legacy_host_projection "$host_conf" "$hosts_file" || rc=113
    fi
    if [[ $rc -eq 0 ]]
    then
        _invalidate_cluster_config_caches || rc=113
    fi
    if [[ $rc -eq 0 ]]
    then
        ## A successful apply is an explicit enrollment. Clear a previous
        ## retirement receipt last, after canonical, projections, modes, and
        ## cache invalidation have all completed.
        rm -f -- "$SC_CLUSTER_CONFIG_RETIRE_MARKER" || rc=113
    fi
    rm -f -- "$temporary_host_conf" "$temporary_hosts"
    return "$rc"
}

function apply_prepared_cluster_config() {
    local prepared="$1" expected_sha="$2"
    local canonical="${3:-/etc/srvctl/clusters.json}"
    local legacy="${4:-/etc/srvctl/data/clusters.json}"
    local host_conf="${5:-$SC_CLUSTER_CONFIG_HOST_DIR/host.conf}"
    local hosts_file="${6:-$SC_CLUSTER_CONFIG_HOST_DIR/hosts.json}"
    _with_cluster_config_lock _apply_prepared_cluster_config_locked \
        "$prepared" "$expected_sha" "$canonical" "$legacy" "$host_conf" "$hosts_file"
}

function _retire_cluster_config_locked() {
    local expected_sha="$1" canonical="$2" legacy="$3"
    local host_conf="$4" hosts_file="$5"
    local actual_sha marker_sha marker_rc

    if [[ ! $expected_sha =~ ^[0-9a-f]{64}$ ]]
    then
        echo "DATA-ERROR: invalid expected cluster retirement SHA-256: $expected_sha" >&2
        return 113
    fi
    audit_cluster_config_paths "$canonical" "$legacy" || return $?
    _validate_existing_cluster_files "$canonical" "$legacy" || return $?

    marker_sha="$(_read_cluster_retire_marker)"
    marker_rc=$?
    if [[ $marker_rc -ne 0 && $marker_rc -ne 100 ]]
    then
        return "$marker_rc"
    fi
    if [[ $marker_rc -eq 0 && $marker_sha != "$expected_sha" ]]
    then
        echo "DATA-ERROR: cluster retirement marker belongs to another generation" >&2
        return 113
    fi

    if [[ -f $canonical ]]
    then
        actual_sha="$(_cluster_config_cli sha256 "$canonical")" || return $?
        if [[ $actual_sha != "$expected_sha" ]]
        then
            echo "DATA-ERROR: refusing to retire unexpected canonical generation: $actual_sha" >&2
            return 113
        fi
        _cluster_config_cli local "$canonical" >/dev/null || return $?
        if [[ $marker_rc -ne 0 ]]
        then
            _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file" >/dev/null || return $?
        fi
        if [[ -f $legacy ]] && ! cmp --silent -- "$legacy" "$canonical"
        then
            echo "DATA-ERROR: refusing retirement with divergent legacy topology: $legacy" >&2
            return 113
        fi
    elif [[ -f $legacy ]]
    then
        actual_sha="$(_cluster_config_cli sha256 "$legacy")" || return $?
        if [[ $actual_sha != "$expected_sha" ]]
        then
            echo "DATA-ERROR: refusing to retire unexpected legacy generation: $actual_sha" >&2
            return 113
        fi
        _cluster_config_cli local "$legacy" >/dev/null || return $?
        if [[ $marker_rc -ne 0 ]]
        then
            _cluster_config_cli verify "$legacy" "$host_conf" "$hosts_file" >/dev/null || return $?
        fi
    elif [[ $marker_rc -ne 0 ]]
    then
        echo "DATA-ERROR: cluster topology is absent without a matching retirement marker" >&2
        return 113
    fi

    ## Commit the generation receipt first. If removal is interrupted, a retry
    ## can prove which exact topology authorized the remaining cleanup.
    if [[ $marker_rc -ne 0 ]]
    then
        _write_cluster_retire_marker "$expected_sha" || return $?
    fi
    rm -f -- "$legacy" "$host_conf" "$hosts_file" "$canonical" \
        "$SC_CLUSTER_CONFIG_LEGACY_HOST_CONF" "$SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE" || return 113
    _invalidate_cluster_config_caches || return 113

    if [[ -e $canonical || -e $legacy || -e $host_conf || -e $hosts_file ]] || \
       [[ -e $SC_CLUSTER_CONFIG_LEGACY_HOST_CONF || -e $SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE ]]
    then
        echo "DATA-ERROR: cluster retirement left live topology or projections" >&2
        return 113
    fi
    echo "$expected_sha"
}

## Detach one decommissioned host from an exact deployed generation. The SHA
## marker makes a retry safe after interruption without retaining topology.
function retire_cluster_config() {
    local expected_sha="$1"
    local canonical="${2:-/etc/srvctl/clusters.json}"
    local legacy="${3:-/etc/srvctl/data/clusters.json}"
    local host_conf="${4:-$SC_CLUSTER_CONFIG_HOST_DIR/host.conf}"
    local hosts_file="${5:-$SC_CLUSTER_CONFIG_HOST_DIR/hosts.json}"
    _with_cluster_config_lock _retire_cluster_config_locked \
        "$expected_sha" "$canonical" "$legacy" "$host_conf" "$hosts_file"
}

function _prepare_cluster_rollback_to_legacy_locked() {
    local canonical="$1" legacy="$2"
    local legacy_parent temporary

    if [[ ! -f $canonical ]]
    then
        echo "DATA-ERROR: canonical clusters configuration is required for a legacy rollback" >&2
        return 113
    fi
    _validate_existing_cluster_files "$canonical" || return $?
    _cluster_config_cli local "$canonical" >/dev/null || return $?
    ## v3 renders host.conf values as UNQUOTED root shell assignments. Refuse
    ## the rollback outright if any host carries a value v3 would evaluate
    ## (whitespace, $(...), quotes, ...) — before anything is written.
    _cluster_config_cli v3safe "$canonical" >/dev/null || return $?

    ## Render the projections at the v3 /etc/srvctl location with the same
    ## atomic generator and verification used for the live ones.
    refresh_cluster_host_config "$canonical" \
        "$SC_CLUSTER_CONFIG_LEGACY_HOST_CONF" \
        "$SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE" || return $?

    ## Restore the v3 update-install seed atomically beside its destination.
    legacy_parent="${legacy%/*}"
    [[ $legacy_parent == "$legacy" ]] && legacy_parent=.
    mkdir -p -- "$legacy_parent" || return 113
    temporary="$(mktemp "$legacy_parent/.clusters.json.rollback.XXXXXX")" || return 113
    if ! cat -- "$canonical" > "$temporary" ||
       ! chmod 644 -- "$temporary" ||
       ! mv -- "$temporary" "$legacy"
    then
        rm -f -- "$temporary"
        return 113
    fi
    _invalidate_cluster_config_caches || return 113
    _cluster_config_cli sha256 "$canonical" || return $?
}

## Reviewed backout for the /var/srvctl3/host relocation and the canonical
## topology migration. Re-creates the v3-era files (/etc/srvctl/host.conf,
## /etc/srvctl/hosts.json, and the /etc/srvctl/data/clusters.json seed) from
## the canonical topology, so a host whose CODE is rolled back to v3 boots
## with a valid identity and its update-install keeps regenerating them.
## Run this WHILE STILL ON v4 code, then immediately replace the code: v4
## non-root invocations fail closed once the legacy projection exists, and
## any later v4 root invocation migrates the legacy files away again.
function prepare_cluster_rollback_to_legacy() {
    local canonical="${1:-/etc/srvctl/clusters.json}"
    local legacy="${2:-/etc/srvctl/data/clusters.json}"
    _with_cluster_config_lock _prepare_cluster_rollback_to_legacy_locked \
        "$canonical" "$legacy"
}
