#!/bin/bash
#
# Two-phase fleet cluster-topology publication tests. All remote operations
# are stubbed; the one explicit real-rsync case uses only a temporary tree.
# Run: bash modules/datastore/selftest/datalib.test.sh

# Test doubles are called indirectly by sourced production functions.
# shellcheck disable=SC2034,SC2329
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

pass=0
fail=0
RC=0

ok() {
    if [[ $2 == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}

TMP="$(mktemp -d)"
MARKFILE="$TMP/marks"
trap '/bin/rm -rf "$TMP"' EXIT
: > "$MARKFILE"
REAL_RSYNC="$(type -P rsync || true)"

echo "== real rsync filter uses the no-trailing-slash transfer root =="
if [[ -n $REAL_RSYNC ]]
then
    mkdir -p "$TMP/real-source/data" "$TMP/real-destination"
    printf '%s\n' '{"legacy":true}' > "$TMP/real-source/data/clusters.json"
    printf '%s\n' '{"backup":true}' > "$TMP/real-source/data/clusters.bak.json"
    printf '%s\n' '{"seed":true}' > "$TMP/real-source/data/seed.json"
    "$REAL_RSYNC" -a '--exclude=/data/clusters*.json' \
        "$TMP/real-source/data" "$TMP/real-destination"
    ok "ordinary seed is copied" \
        "$([[ -f $TMP/real-destination/data/seed.json ]] && echo yes || echo no)" "yes"
    ok "legacy topology is excluded" \
        "$([[ -e $TMP/real-destination/data/clusters.json ]] && echo no || echo yes)" "yes"
    ok "legacy topology backup is excluded" \
        "$([[ -e $TMP/real-destination/data/clusters.bak.json ]] && echo no || echo yes)" "yes"
else
    echo "  SKIP real-rsync check: rsync is not installed"
fi

# shellcheck source=/dev/null
source "$REPO/modules/datastore/libs/datalib.sh"

EXPECTED_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

echo "== publication state stores inventory proof, not topology =="
SC_CLUSTER_PUBLICATION_STATE_DIR="$TMP/real-publication-state"
_cluster_store_publication_manifest "$EXPECTED_SHA" \
    local.example alpha.example
state_manifest="$(_cluster_load_publication_manifest)"
ok "manifest round trips exact SHA and ordered hostnames" "$state_manifest" \
    $'sha256\t'"$EXPECTED_SHA"$'\nhost\tlocal.example\nhost\talpha.example'
ok "manifest contains no JSON topology fields" \
    "$([[ $(<"$SC_CLUSTER_PUBLICATION_STATE_DIR/publication-inventory.v1") == *'{'* || \
          $(<"$SC_CLUSTER_PUBLICATION_STATE_DIR/publication-inventory.v1") == *dns_server* ]] && echo no || echo yes)" yes
if verify_cluster_publication_inventory "$EXPECTED_SHA" local.example alpha.example
then inventory_match_rc=0; else inventory_match_rc=$?; fi
ok "published inventory verifier accepts exact SHA and order" "$inventory_match_rc" 0
if verify_cluster_publication_inventory "$EXPECTED_SHA" local.example
then inventory_removed_rc=0; else inventory_removed_rc=$?; fi
ok "published inventory verifier catches a removed host" "$inventory_removed_rc" 1
if verify_cluster_publication_inventory \
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    local.example alpha.example
then inventory_sha_rc=0; else inventory_sha_rc=$?; fi
ok "published inventory verifier catches a different SHA" "$inventory_sha_rc" 1
printf 'version\t1\nsha256\t%s\nhost\tlocal.example' "$EXPECTED_SHA" \
    > "$SC_CLUSTER_PUBLICATION_STATE_DIR/publication-inventory.v1"
if _cluster_load_publication_manifest >/dev/null 2>&1
then truncated_manifest_rc=0; else truncated_manifest_rc=$?; fi
ok "truncated final inventory record fails closed" "$truncated_manifest_rc" 113
_cluster_store_publication_manifest "$EXPECTED_SHA" local.example alpha.example
_cluster_store_retirement_receipt alpha.example "$EXPECTED_SHA"
ok "retirement receipt is exact-generation proof" \
    "$(_cluster_read_retirement_receipt alpha.example)" "$EXPECTED_SHA"
_cluster_consume_retirement_receipt alpha.example
ok "retirement receipt is consumable after publication" \
    "$(_cluster_read_retirement_receipt alpha.example >/dev/null 2>&1; echo $?)" 100
unset SC_CLUSTER_PUBLICATION_STATE_DIR

HOSTNAME="local.example"
HOST_OUTPUT=$'local.example\nalpha.example\ncross-cluster.example'
MANIFEST_PRESENT=1
MANIFEST_INVALID=0
MANIFEST_SHA="$EXPECTED_SHA"
MANIFEST_HOST_OUTPUT=$'local.example\nalpha.example\ncross-cluster.example'
MANIFEST_STORE_FAIL=0
RECEIPT_STORE_FAIL=0
RECEIPT_CONSUME_FAIL=0
WORKFLOW_LOCK_RC=0
LOCAL_VERIFY_RC=0
LOCAL_CAPABILITY_RC=0
LOCAL_APPLY_RC=0
ROOT_RC=0
LOCK_ACQUIRE_RC=0
LOCK_RELEASE_RC=0
GRAB_INVALID=0
LOCAL_SHA_CALLS=0
LOCAL_SHA_CHANGE_AT=0
PROBE_FAIL_HOST=""
RSYNC_FAIL_SOURCE=""
RSYNC_FAIL_DEST=""
LOCAL_MKDIR_FAIL=0
declare -A CAPABILITY_FAIL=()
declare -A STATIC_FAIL=()
declare -A STAGE_FAIL=()
declare -A PREPARE_FAIL=()
declare -A PREPARE_SHA=()
declare -A COMMIT_FAIL=()
declare -A REMOTE_SHA=()
declare -A PROJECTION_SHA=()
declare -A CLEANUP_FAIL=()
declare -A RETIREMENT_RECEIPT=()
declare -A RETIRE_CAPABILITY_FAIL=()
declare -A QUIESCE_FAIL=()
declare -A RETIRE_FAIL=()
declare -A REMOTE_ALREADY_RETIRED=()

mark() {
    local label="$1" value
    shift
    printf '%s' "$label" >> "$MARKFILE"
    for value in "$@"
    do
        printf '|%s' "$value" >> "$MARKFILE"
    done
    printf '\n' >> "$MARKFILE"
}

count_mark() {
    local wanted="$1" count=0 line
    while IFS= read -r line
    do
        [[ $line == "$wanted" ]] && count=$((count + 1))
    done < "$MARKFILE"
    printf '%s\n' "$count"
}

count_prefix() {
    local wanted="$1" count=0 line
    while IFS= read -r line
    do
        [[ $line == "$wanted"* ]] && count=$((count + 1))
    done < "$MARKFILE"
    printf '%s\n' "$count"
}

line_number() {
    local wanted="$1" line number=0
    while IFS= read -r line
    do
        number=$((number + 1))
        [[ $line == "$wanted"* ]] && { printf '%s\n' "$number"; return; }
    done < "$MARKFILE"
    printf '0\n'
}

has_error() {
    local wanted="$1" line
    while IFS= read -r line
    do
        [[ $line == err\|*"$wanted"* ]] && { echo yes; return; }
    done < "$MARKFILE"
    echo no
}

msg() { mark msg "$@"; }
err() { mark err "$@"; }

_cluster_config_require_root() { return "$ROOT_RC"; }

_with_cluster_publication_workflow_lock() {
    local callback="$1" rc
    shift
    mark workflow-lock "$callback"
    [[ $WORKFLOW_LOCK_RC -eq 0 ]] || return "$WORKFLOW_LOCK_RC"
    "$callback" "$@"
    rc=$?
    mark workflow-unlock "$callback"
    return "$rc"
}

_cluster_load_publication_manifest() {
    local host
    mark manifest-load
    [[ $MANIFEST_INVALID -eq 0 ]] || return 113
    [[ $MANIFEST_PRESENT -eq 1 ]] || return 100
    printf 'sha256\t%s\n' "$MANIFEST_SHA"
    while IFS= read -r host
    do
        [[ -n $host ]] && printf 'host\t%s\n' "$host"
    done <<< "$MANIFEST_HOST_OUTPUT"
}

_cluster_store_publication_manifest() {
    local sha="$1" host output=""
    shift
    mark manifest-store "$sha" "$@"
    [[ $MANIFEST_STORE_FAIL -eq 0 ]] || return 113
    MANIFEST_PRESENT=1
    MANIFEST_SHA="$sha"
    for host in "$@"
    do
        output+="$host"$'\n'
    done
    MANIFEST_HOST_OUTPUT="${output%$'\n'}"
}

_cluster_read_retirement_receipt() {
    local host="$1"
    mark receipt-read "$host"
    [[ -v RETIREMENT_RECEIPT["$host"] ]] || return 100
    printf '%s\n' "${RETIREMENT_RECEIPT["$host"]}"
}

_cluster_store_retirement_receipt() {
    local host="$1" sha="$2"
    mark receipt-store "$host" "$sha"
    [[ $RECEIPT_STORE_FAIL -eq 0 ]] || return 113
    RETIREMENT_RECEIPT["$host"]="$sha"
}

_cluster_consume_retirement_receipt() {
    local host="$1"
    mark receipt-consume "$host"
    [[ $RECEIPT_CONSUME_FAIL -eq 0 ]] || return 113
    unset 'RETIREMENT_RECEIPT[$host]'
}

_srvctl_cluster_cli() {
    local command="$1" path="$2" call_count
    shift 2
    mark cli "$command" "$path" "$@"
    case "$command" in
        hosts)
            printf '%s\n' "$HOST_OUTPUT"
            ;;
        sha256)
            if [[ $path == *'.srvctl-grab.'* && $GRAB_INVALID -eq 1 ]]
            then
                return 113
            fi
            if [[ $path == /etc/srvctl/clusters.json ]]
            then
                call_count="$(count_mark 'cli|sha256|/etc/srvctl/clusters.json')"
                if [[ $LOCAL_SHA_CHANGE_AT -gt 0 && $call_count -ge $LOCAL_SHA_CHANGE_AT ]]
                then
                    printf '%064d\n' 0
                    return 0
                fi
            fi
            printf '%s\n' "$EXPECTED_SHA"
            ;;
        verify)
            [[ $LOCAL_VERIFY_RC -eq 0 ]] || return "$LOCAL_VERIFY_RC"
            printf '%s\n' "$EXPECTED_SHA"
            ;;
        *)
            return 113
            ;;
    esac
}

_cluster_remote_capability() {
    local host="$1"
    mark capability "$host"
    [[ ${CAPABILITY_FAIL["$host"]:-0} -eq 0 ]]
}

_cluster_remote_retirement_capability() {
    local host="$1"
    mark retire-capability "$host"
    [[ ${RETIRE_CAPABILITY_FAIL["$host"]:-0} -eq 0 ]]
}

_cluster_quiesce_remote_retired_roles() {
    local host="$1"
    mark quiesce "$host"
    [[ ${QUIESCE_FAIL["$host"]:-0} -eq 0 ]]
}

_cluster_retire_remote() {
    local host="$1" sha="$2"
    mark retire "$host" "$sha"
    [[ ${RETIRE_FAIL["$host"]:-0} -eq 0 ]] || return 113
    printf '%s\n' "$sha"
}

_cluster_verify_remote_retired() {
    local host="$1" sha="$2"
    mark retired-verify "$host" "$sha"
    [[ ${REMOTE_ALREADY_RETIRED["$host"]:-0} -eq 1 ]] ||
        [[ $(count_mark "retire|$host|$sha") -gt 0 ]]
}

_cluster_publish_static_to() {
    local host="$1"
    mark static "$host"
    [[ ${STATIC_FAIL["$host"]:-0} -eq 0 ]]
}

_cluster_stage_to() {
    local host="$1"
    mark stage "$host"
    [[ ${STAGE_FAIL["$host"]:-0} -eq 0 ]]
}

_cluster_validate_remote_prepared() {
    local host="$1"
    mark prepare "$host"
    [[ ${PREPARE_FAIL["$host"]:-0} -eq 0 ]] || return 113
    printf '%s\n' "${PREPARE_SHA["$host"]:-$EXPECTED_SHA}"
}

_cluster_apply_remote_prepared() {
    local host="$1"
    mark commit "$host"
    [[ ${COMMIT_FAIL["$host"]:-0} -eq 0 ]]
}

_cluster_remote_sha() {
    local host="$1"
    mark remote-sha "$host"
    printf '%s\n' "${REMOTE_SHA["$host"]:-$EXPECTED_SHA}"
}

_cluster_verify_remote_projection() {
    local host="$1"
    mark remote-projection "$host"
    printf '%s\n' "${PROJECTION_SHA["$host"]:-$EXPECTED_SHA}"
}

_cluster_cleanup_remote_prepared() {
    local host="$1"
    mark cleanup "$host"
    [[ ${CLEANUP_FAIL["$host"]:-0} -eq 0 ]]
}

_cluster_acquire_local_publication_lock() {
    local result_variable="$1"
    mark lock-acquire
    [[ $LOCK_ACQUIRE_RC -eq 0 ]] || return "$LOCK_ACQUIRE_RC"
    printf -v "$result_variable" '%s' 99
}

_cluster_release_local_publication_lock() {
    mark lock-release "$1"
    return "$LOCK_RELEASE_RC"
}

_cluster_local_capability() {
    mark local-capability
    [[ $LOCAL_CAPABILITY_RC -eq 0 ]]
}

_cluster_apply_local_prepared() {
    mark local-apply "$@"
    [[ $LOCAL_APPLY_RC -eq 0 ]]
}

# Low-level doubles are used by static grab and staged topology import.
ssh() {
    local host command
    local -a arguments=("$@")
    host="${arguments[${#arguments[@]} - 2]}"
    command="${arguments[${#arguments[@]} - 1]}"
    mark ssh "$@"
    if [[ $command == hostname ]]
    then
        [[ $host != "$PROBE_FAIL_HOST" ]] || return 255
        printf '%s\n' "$host"
    fi
}

rsync() {
    local source destination
    local -a arguments=("$@")
    source="${arguments[${#arguments[@]} - 2]}"
    destination="${arguments[${#arguments[@]} - 1]}"
    mark rsync "$@"
    if [[ -n $RSYNC_FAIL_SOURCE && $source == "$RSYNC_FAIL_SOURCE" &&
          -n $RSYNC_FAIL_DEST && $destination == "$RSYNC_FAIL_DEST" ]]
    then
        return 23
    fi
}

mkdir() {
    mark mkdir "$@"
    [[ $LOCAL_MKDIR_FAIL -eq 0 ]]
}

rm() {
    mark rm "$@"
    return 0
}

reset_probe() {
    : > "$MARKFILE"
    HOST_OUTPUT=$'local.example\nalpha.example\ncross-cluster.example'
    MANIFEST_PRESENT=1
    MANIFEST_INVALID=0
    MANIFEST_SHA="$EXPECTED_SHA"
    MANIFEST_HOST_OUTPUT=$'local.example\nalpha.example\ncross-cluster.example'
    MANIFEST_STORE_FAIL=0
    RECEIPT_STORE_FAIL=0
    RECEIPT_CONSUME_FAIL=0
    WORKFLOW_LOCK_RC=0
    LOCAL_VERIFY_RC=0
    LOCAL_CAPABILITY_RC=0
    LOCAL_APPLY_RC=0
    ROOT_RC=0
    LOCK_ACQUIRE_RC=0
    LOCK_RELEASE_RC=0
    GRAB_INVALID=0
    LOCAL_SHA_CALLS=0
    LOCAL_SHA_CHANGE_AT=0
    PROBE_FAIL_HOST=""
    RSYNC_FAIL_SOURCE=""
    RSYNC_FAIL_DEST=""
    LOCAL_MKDIR_FAIL=0
    CAPABILITY_FAIL=()
    STATIC_FAIL=()
    STAGE_FAIL=()
    PREPARE_FAIL=()
    PREPARE_SHA=()
    COMMIT_FAIL=()
    REMOTE_SHA=()
    PROJECTION_SHA=()
    CLEANUP_FAIL=()
    RETIREMENT_RECEIPT=()
    RETIRE_CAPABILITY_FAIL=()
    QUIESCE_FAIL=()
    RETIRE_FAIL=()
    REMOTE_ALREADY_RETIRED=()
}

run_publish() {
    if publish_data
    then RC=0; else RC=$?; fi
}

run_initialize() {
    if initialize_cluster_publication "$@"
    then RC=0; else RC=$?; fi
}

run_retire() {
    if retire_cluster_host "$@"
    then RC=0; else RC=$?; fi
}

run_grab_data() {
    if grab_data "$1"
    then RC=0; else RC=$?; fi
}

run_grab_cluster() {
    if grab_cluster_config "$1"
    then RC=0; else RC=$?; fi
}

echo "== first publication requires a verified explicit baseline =="
reset_probe
MANIFEST_PRESENT=0
run_publish
ok "ordinary publication fails without a baseline" "$RC" 1
ok "missing baseline is explicit" \
    "$(has_error 'initialize_cluster_publication confirm-complete-inventory')" yes
ok "missing baseline mutates no remote" "$(count_prefix 'capability|')" 0

reset_probe
MANIFEST_PRESENT=0
run_initialize
ok "baseline requires exact confirmation" "$RC" 1
ok "unconfirmed baseline stores nothing" "$(count_prefix 'manifest-store|')" 0

reset_probe
MANIFEST_PRESENT=0
run_initialize confirm-complete-inventory
ok "verified baseline succeeds" "$RC" 0
ok "baseline verifies every remote capability" "$(count_prefix 'capability|')" 2
ok "baseline verifies every remote canonical SHA" "$(count_prefix 'remote-sha|')" 2
ok "baseline verifies every remote projection" "$(count_prefix 'remote-projection|')" 2
ok "baseline stores SHA and ordered inventory" \
    "$(count_mark "manifest-store|$EXPECTED_SHA|local.example|alpha.example|cross-cluster.example")" 1
ok "baseline rechecks source under topology lock" \
    "$(( $(line_number 'lock-acquire') < $(line_number 'manifest-store|') ))" 1

reset_probe
MANIFEST_PRESENT=0
PROJECTION_SHA[alpha.example]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
run_initialize confirm-complete-inventory
ok "baseline refuses a drifting remote" "$RC" 1
ok "drifting baseline stores nothing" "$(count_prefix 'manifest-store|')" 0

reset_probe
MANIFEST_PRESENT=0
LOCAL_SHA_CHANGE_AT=2
run_initialize confirm-complete-inventory
ok "baseline refuses a source race" "$RC" 1
ok "source-raced baseline stores nothing" "$(count_prefix 'manifest-store|')" 0
ok "source-raced baseline releases topology lock" "$(count_prefix 'lock-release|')" 1

echo "== removal requires exact-generation retirement proof =="
reset_probe
HOST_OUTPUT=$'local.example\nalpha.example'
run_publish
ok "silent host removal fails" "$RC" 1
ok "silent removal is identified" \
    "$(has_error 'cross-cluster.example was removed without retiring deployed generation')" yes
ok "silent removal mutates no remote" "$(count_prefix 'capability|')" 0

reset_probe
HOST_OUTPUT=$'local.example\nalpha.example'
RETIREMENT_RECEIPT[cross-cluster.example]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
run_publish
ok "wrong-generation removal receipt fails" "$RC" 1
ok "wrong-generation removal mutates no remote" "$(count_prefix 'capability|')" 0

reset_probe
HOST_OUTPUT=$'local.example\nalpha.example'
RETIREMENT_RECEIPT[cross-cluster.example]="$EXPECTED_SHA"
run_publish
ok "retired host removal publishes" "$RC" 0
ok "removed host is not contacted" "$(count_mark 'capability|cross-cluster.example')" 0
ok "new inventory is committed to manifest" \
    "$(count_mark "manifest-store|$EXPECTED_SHA|local.example|alpha.example")" 1
ok "consumed removal receipt is deleted" \
    "$([[ -v RETIREMENT_RECEIPT[cross-cluster.example] ]] && echo no || echo yes)" yes

reset_probe
RETIREMENT_RECEIPT[alpha.example]="$EXPECTED_SHA"
run_publish
ok "canonical topology cannot silently re-enroll a retired hostname" "$RC" 1
ok "retired current host is rejected before remote mutation" \
    "$(count_prefix 'capability|')" 0

echo "== host retirement quiesces DNS before detaching topology =="
reset_probe
run_retire cross-cluster.example confirm-decommissioned
ok "exact-generation retirement succeeds" "$RC" 0
ok "retirement capability is preflighted" \
    "$(count_mark 'retire-capability|cross-cluster.example')" 1
ok "authoritative DNS is quiesced" "$(count_mark 'quiesce|cross-cluster.example')" 1
ok "DNS stop precedes topology retirement" \
    "$(( $(line_number 'quiesce|cross-cluster.example') < $(line_number 'retire|cross-cluster.example') ))" 1
ok "remote retirement is verified before local receipt" \
    "$(( $(line_number 'retire|cross-cluster.example') < $(line_number 'receipt-store|cross-cluster.example') ))" 1
ok "retirement stores exact manifest generation" \
    "${RETIREMENT_RECEIPT[cross-cluster.example]:-}" "$EXPECTED_SHA"

reset_probe
RETIRE_CAPABILITY_FAIL[cross-cluster.example]=1
run_retire cross-cluster.example confirm-decommissioned
ok "old helper without retirement capability fails" "$RC" 1
ok "capability failure leaves named running" \
    "$(count_mark 'quiesce|cross-cluster.example')" 0
ok "capability failure detaches no topology" \
    "$(count_mark "retire|cross-cluster.example|$EXPECTED_SHA")" 0

reset_probe
REMOTE_SHA[cross-cluster.example]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
run_retire cross-cluster.example confirm-decommissioned
ok "unexpected live generation cannot retire" "$RC" 1
ok "generation mismatch leaves named running" \
    "$(count_mark 'quiesce|cross-cluster.example')" 0

reset_probe
QUIESCE_FAIL[cross-cluster.example]=1
run_retire cross-cluster.example confirm-decommissioned
ok "named quiesce failure aborts retirement" "$RC" 1
ok "quiesce failure detaches no topology" \
    "$(count_mark "retire|cross-cluster.example|$EXPECTED_SHA")" 0
ok "quiesce failure stores no receipt" \
    "$(count_mark 'receipt-store|cross-cluster.example')" 0

reset_probe
REMOTE_ALREADY_RETIRED[cross-cluster.example]=1
run_retire cross-cluster.example confirm-decommissioned
ok "missing local receipt recovers from remote retirement marker" "$RC" 0
ok "receipt recovery needs no live remote canonical" \
    "$(count_mark 'remote-sha|cross-cluster.example')" 0
ok "receipt recovery does not stop named twice" \
    "$(count_mark 'quiesce|cross-cluster.example')" 0
ok "receipt recovery recreates exact proof" \
    "${RETIREMENT_RECEIPT[cross-cluster.example]:-}" "$EXPECTED_SHA"

reset_probe
RECEIPT_STORE_FAIL=1
run_retire cross-cluster.example confirm-decommissioned
first_retire_rc="$RC"
RECEIPT_STORE_FAIL=0
run_retire cross-cluster.example confirm-decommissioned
ok "remote success with local receipt failure is loud" "$first_retire_rc" 1
ok "same retirement command recovers on retry" "$RC" 0
ok "receipt retry does not detach topology twice" \
    "$(count_mark "retire|cross-cluster.example|$EXPECTED_SHA")" 1

reset_probe
RETIREMENT_RECEIPT[cross-cluster.example]="$EXPECTED_SHA"
REMOTE_ALREADY_RETIRED[cross-cluster.example]=1
run_retire cross-cluster.example confirm-decommissioned
ok "verified existing receipt makes retirement idempotent" "$RC" 0
ok "idempotent receipt path does not stop named again" \
    "$(count_mark 'quiesce|cross-cluster.example')" 0

echo "== publication-state workflows share one exclusive gate =="
reset_probe
WORKFLOW_LOCK_RC=113
run_publish
publish_busy_rc="$RC"
run_retire cross-cluster.example confirm-decommissioned
ok "busy workflow gate blocks publication" "$publish_busy_rc" 113
ok "same busy gate blocks retirement" "$RC" 113
ok "blocked workflows inspect no topology or remote" \
    "$(( $(count_prefix 'cli|') + $(count_prefix 'capability|') ))" 0

echo "== successful cross-cluster two-phase publication =="
reset_probe
run_publish
ok "publish succeeds" "$RC" "0"
ok "local source does not require self SSH" "$(count_mark 'capability|local.example')" "0"
ok "current-cluster remote is discovered" "$(count_mark 'capability|alpha.example')" "1"
ok "cross-cluster remote is discovered" "$(count_mark 'capability|cross-cluster.example')" "1"
ok "both remotes receive static seeds" "$(count_prefix 'static|')" "2"
ok "both remotes are staged" "$(count_prefix 'stage|')" "2"
ok "both remotes are prepared" "$(count_prefix 'prepare|')" "2"
ok "both remotes are committed" "$(count_prefix 'commit|')" "2"
ok "remote canonical SHA is verified" "$(count_prefix 'remote-sha|')" "2"
ok "remote projections are verified" "$(count_prefix 'remote-projection|')" "2"
ok "all capabilities precede static mutation" \
    "$(( $(line_number 'capability|cross-cluster.example') < $(line_number 'static|alpha.example') ))" "1"
ok "all stages precede first commit" \
    "$(( $(line_number 'stage|cross-cluster.example') < $(line_number 'commit|alpha.example') ))" "1"
ok "all prepare audits precede first commit" \
    "$(( $(line_number 'prepare|cross-cluster.example') < $(line_number 'commit|alpha.example') ))" "1"
ok "publication lock precedes first commit" \
    "$(( $(line_number 'lock-acquire') < $(line_number 'commit|alpha.example') ))" "1"
ok "publication lock covers final verification" \
    "$(( $(line_number 'remote-projection|cross-cluster.example') < $(line_number 'lock-release') ))" "1"

echo "== duplicate inventory is defensive and deterministic =="
reset_probe
HOST_OUTPUT=$'local.example\nalpha.example\nalpha.example\ncross-cluster.example'
run_publish
ok "duplicate host is acted on once" "$(count_mark 'commit|alpha.example')" "1"
ok "deduplicated publish succeeds" "$RC" "0"

echo "== mixed-version preflight makes no mutation =="
reset_probe
CAPABILITY_FAIL[cross-cluster.example]=1
run_publish
ok "mixed-version fleet fails" "$RC" "1"
ok "all capability failures aggregate" "$(count_prefix 'capability|')" "2"
ok "preflight failure syncs no static data" "$(count_prefix 'static|')" "0"
ok "preflight failure stages nothing" "$(count_prefix 'stage|')" "0"
ok "preflight failure commits nothing" "$(count_prefix 'commit|')" "0"

echo "== static failure precedes topology prepare =="
reset_probe
STATIC_FAIL[alpha.example]=1
run_publish
ok "static failure propagates" "$RC" "1"
ok "later static host is still attempted" "$(count_mark 'static|cross-cluster.example')" "1"
ok "static failure stages no topology" "$(count_prefix 'stage|')" "0"

echo "== stage and legacy prepare failures have zero commits =="
reset_probe
STAGE_FAIL[cross-cluster.example]=1
run_publish
ok "stage failure propagates" "$RC" "1"
ok "stage failure commits nothing" "$(count_prefix 'commit|')" "0"
ok "stage failure cleans every target" "$(count_prefix 'cleanup|')" "2"
ok "stage failure explains no commit" "$(has_error 'no canonical topology was committed')" "yes"

reset_probe
# The core non-mutating validator reports this for a divergent legacy path.
PREPARE_FAIL[cross-cluster.example]=1
run_publish
ok "divergent legacy prepare fails" "$RC" "1"
ok "legacy conflict commits nothing" "$(count_prefix 'commit|')" "0"
ok "legacy conflict cleans all prepared files" "$(count_prefix 'cleanup|')" "2"

reset_probe
PREPARE_SHA[cross-cluster.example]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
run_publish
ok "prepared SHA mismatch fails" "$RC" "1"
ok "prepared SHA mismatch commits nothing" "$(count_prefix 'commit|')" "0"

echo "== source change after prepare aborts before commit =="
reset_probe
LOCAL_SHA_CHANGE_AT=2
run_publish
ok "source race fails" "$RC" "1"
ok "source race commits nothing" "$(count_prefix 'commit|')" "0"
ok "source race cleans all prepared files" "$(count_prefix 'cleanup|')" "2"
ok "source race releases publication lock" "$(count_prefix 'lock-release|')" "1"

reset_probe
LOCK_ACQUIRE_RC=113
run_publish
ok "publication lock failure propagates" "$RC" "1"
ok "publication lock failure commits nothing" "$(count_prefix 'commit|')" "0"
ok "publication lock failure cleans prepared files" "$(count_prefix 'cleanup|')" "2"

echo "== partial commit is loud and all hosts are verified =="
reset_probe
COMMIT_FAIL[cross-cluster.example]=1
# Simulate apply moving the canonical file before failing a derived rename.
REMOTE_SHA[cross-cluster.example]="$EXPECTED_SHA"
PROJECTION_SHA[cross-cluster.example]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
run_publish
ok "partial commit returns nonzero" "$RC" "1"
ok "commit continues across hosts" "$(count_prefix 'commit|')" "2"
ok "partial commit verifies all hashes" "$(count_prefix 'remote-sha|')" "2"
ok "partial commit verifies all projections" "$(count_prefix 'remote-projection|')" "2"
ok "partial commit is explicit" "$(has_error 'PARTIAL CLUSTER TOPOLOGY COMMIT')" "yes"

reset_probe
HOST_OUTPUT=$'local.example\nalpha.example'
MANIFEST_HOST_OUTPUT=$'local.example\nalpha.example'
COMMIT_FAIL[alpha.example]=1
PROJECTION_SHA[alpha.example]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
run_publish
ok "single-remote post-canonical failure is nonzero" "$RC" "1"
ok "single-remote canonical match is classified partial" \
    "$(has_error 'PARTIAL CLUSTER TOPOLOGY COMMIT')" "yes"

reset_probe
REMOTE_SHA[cross-cluster.example]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
run_publish
ok "post-commit SHA mismatch fails" "$RC" "1"
ok "verified peer makes mismatch partial" "$(has_error 'PARTIAL CLUSTER TOPOLOGY COMMIT')" "yes"

echo "== local projection failure aborts before remote preflight =="
reset_probe
LOCAL_VERIFY_RC=113
run_publish
ok "stale local projection fails" "$RC" "1"
ok "local failure contacts no remotes" "$(count_prefix 'capability|')" "0"

echo "== topology writers require root =="
reset_probe
ROOT_RC=1
run_publish
ok "non-root publish fails" "$RC" "1"
ok "non-root publish validates nothing" "$(count_prefix 'cli|')" "0"

reset_probe
ROOT_RC=1
run_grab_cluster source.example
ok "non-root topology grab fails" "$RC" "1"
ok "non-root topology grab contacts no source" "$(count_prefix 'capability|')" "0"

echo "== grab_data remains static-only =="
reset_probe
run_grab_data source.example
ok "static grab succeeds" "$RC" "0"
ok "static grab excludes legacy topology" \
    "$(count_prefix 'rsync|-avz|-e|ssh -o BatchMode=yes -o ConnectTimeout=3|--exclude=/data/clusters*.json|source.example:/etc/srvctl/data|/etc/srvctl')" "1"
ok "static grab never fetches canonical topology" \
    "$(count_prefix 'rsync|-avz|-e|ssh -o BatchMode=yes -o ConnectTimeout=3|source.example:/etc/srvctl/clusters.json')" "0"

reset_probe
RSYNC_FAIL_SOURCE="source.example:/etc/srvctl/data"
RSYNC_FAIL_DEST="/etc/srvctl"
run_grab_data source.example
ok "static grab failure propagates" "$RC" "1"

echo "== grab_cluster_config is an explicit staged apply =="
reset_probe
run_grab_cluster source.example
ok "topology grab succeeds" "$RC" "0"
ok "topology source is capability checked" "$(count_mark 'capability|source.example')" "1"
ok "local apply capability is checked" "$(count_mark 'local-capability')" "1"
ok "topology is downloaded only to prepared path" \
    "$(count_prefix 'rsync|-avz|-e|ssh -o BatchMode=yes -o ConnectTimeout=3|source.example:/etc/srvctl/clusters.json|/etc/srvctl/.clusters.json.srvctl-grab.')" "1"
ok "validated prepared topology uses locked apply" "$(count_prefix 'local-apply|')" "1"

reset_probe
GRAB_INVALID=1
run_grab_cluster source.example
ok "invalid topology grab fails" "$RC" "1"
ok "invalid download is never applied" "$(count_prefix 'local-apply|')" "0"
ok "invalid prepared file is cleaned" "$(count_prefix 'rm|-f|--|/etc/srvctl/.clusters.json.srvctl-grab.')" "2"

reset_probe
LOCAL_APPLY_RC=113
run_grab_cluster source.example
ok "local apply failure propagates" "$RC" "1"
ok "failed local apply cleans prepared file" \
    "$([[ $(count_prefix 'rm|-f|--|/etc/srvctl/.clusters.json.srvctl-grab.') -ge 2 ]] && echo yes || echo no)" "yes"

reset_probe
CAPABILITY_FAIL[source.example]=1
run_grab_cluster source.example
ok "mixed-version topology source fails" "$RC" "1"
ok "mixed-version source downloads nothing" "$(count_prefix 'rsync|')" "0"

## The publication tests above stub mkdir/rm as marks; from here on the
## datastore-layout tests need the real filesystem commands.
unset -f mkdir rm

echo "== marker-less per-entity datastore is blessed authoritative =="
SC_DATASTORE_RW_DIR="$TMP/ds-markerless"
mkdir -p "$SC_DATASTORE_RW_DIR/hosts" "$SC_DATASTORE_RW_DIR/users" "$SC_DATASTORE_RW_DIR/containers"
printf '{"host_key":"k"}\n' > "$SC_DATASTORE_RW_DIR/hosts/h1.json"
migrate_datastore_to_per_entity
ok "blessing returns success" "$?" "0"
ok "marker stamped on marker-less per-entity store" \
    "$([[ -f $SC_DATASTORE_RW_DIR/.per-entity ]] && echo yes || echo no)" "yes"
ok "per-entity record untouched" "$(<"$SC_DATASTORE_RW_DIR/hosts/h1.json")" '{"host_key":"k"}'

echo "== fresh empty datastore is not blessed =="
SC_DATASTORE_RW_DIR="$TMP/ds-fresh"
mkdir -p "$SC_DATASTORE_RW_DIR"
migrate_datastore_to_per_entity
ok "fresh store returns success" "$?" "0"
ok "no marker on a store without per-entity layout" \
    "$([[ -e $SC_DATASTORE_RW_DIR/.per-entity ]] && echo no || echo yes)" "yes"

echo "== partial monolithic without hosts.json fails loudly =="
SC_DATASTORE_RW_DIR="$TMP/ds-partial"
mkdir -p "$SC_DATASTORE_RW_DIR/hosts"
printf '{}\n' > "$SC_DATASTORE_RW_DIR/users.json"
migrate_datastore_to_per_entity
ok "partial monolithic store fails" "$?" "1"
ok "partial monolithic store is not blessed" \
    "$([[ -e $SC_DATASTORE_RW_DIR/.per-entity ]] && echo no || echo yes)" "yes"

echo "== partial per-entity layout is refused (standalone) =="
SC_DATASTORE_RW_DIR="$TMP/ds-partial-dirs"
mkdir -p "$SC_DATASTORE_RW_DIR/hosts"
printf '{"host_key":"k"}\n' > "$SC_DATASTORE_RW_DIR/hosts/h1.json"
migrate_datastore_to_per_entity
ok "hosts-only layout fails" "$?" "1"
ok "hosts-only layout is not blessed" \
    "$([[ -e $SC_DATASTORE_RW_DIR/.per-entity ]] && echo no || echo yes)" "yes"

echo "== real install path: fresh store seeds, migrates, blesses =="
run() { "$@"; }
USER=root
SC_INSTALL_DIR="$REPO"
SC_DATASTORE_SEED_DIR="$TMP/seed-data"
SC_CLUSTER_CONFIG_HOST_DIR="$TMP/host-projection"
mkdir -p "$SC_DATASTORE_SEED_DIR" "$SC_CLUSTER_CONFIG_HOST_DIR"
printf '{"h1.test":{"host_key":"k"}}\n' > "$SC_CLUSTER_CONFIG_HOST_DIR/hosts.json"
SC_DATASTORE_RW_DIR="$TMP/ds-real-fresh"
SC_DATASTORE_RO_DIR="$TMP/ds-real-fresh-ro"
init_datastore_install > /dev/null
ok "real fresh install succeeds" "$?" "0"
ok "real fresh install marks per-entity authoritative" \
    "$([[ -f $SC_DATASTORE_RW_DIR/.per-entity ]] && echo yes || echo no)" "yes"
ok "monolithic hosts seed converted to per-entity" \
    "$([[ -f $SC_DATASTORE_RW_DIR/hosts/h1.test.json ]] && echo yes || echo no)" "yes"
ok "entity skeleton exists" \
    "$([[ -d $SC_DATASTORE_RW_DIR/hosts && -d $SC_DATASTORE_RW_DIR/users && -d $SC_DATASTORE_RW_DIR/containers && -d $SC_DATASTORE_RW_DIR/cert ]] && echo yes || echo no)" "yes"

echo "== real install path: missing projection fails cleanly =="
SC_CLUSTER_CONFIG_HOST_DIR="$TMP/host-projection-absent"
SC_DATASTORE_RW_DIR="$TMP/ds-real-noproj"
SC_DATASTORE_RO_DIR="$TMP/ds-real-noproj-ro"
init_datastore_install > /dev/null
ok "missing projection fails the install" "$?" "1"
ok "no empty hosts.json is left behind" \
    "$([[ -e $SC_DATASTORE_RW_DIR/hosts.json ]] && echo no || echo yes)" "yes"
ok "no marker after the failed install" \
    "$([[ -e $SC_DATASTORE_RW_DIR/.per-entity ]] && echo no || echo yes)" "yes"

echo "== real install path: hosts-only restore is refused =="
SC_CLUSTER_CONFIG_HOST_DIR="$TMP/host-projection"
SC_DATASTORE_RW_DIR="$TMP/ds-real-hostsonly"
SC_DATASTORE_RO_DIR="$TMP/ds-real-hostsonly-ro"
mkdir -p "$SC_DATASTORE_RW_DIR/hosts"
printf '{"host_key":"k"}\n' > "$SC_DATASTORE_RW_DIR/hosts/h1.test.json"
init_datastore_install > /dev/null
ok "partial restore fails through the real install" "$?" "1"
ok "partial restore is never blessed despite normalization" \
    "$([[ -e $SC_DATASTORE_RW_DIR/.per-entity ]] && echo no || echo yes)" "yes"
ok "restored record is untouched" \
    "$(<"$SC_DATASTORE_RW_DIR/hosts/h1.test.json")" '{"host_key":"k"}'

echo "== real install path: surviving monolithic users.json is never clobbered =="
SC_DATASTORE_RW_DIR="$TMP/ds-real-usersjson"
SC_DATASTORE_RO_DIR="$TMP/ds-real-usersjson-ro"
mkdir -p "$SC_DATASTORE_RW_DIR"
printf '{"sentinel":{"role":"user"}}\n' > "$SC_DATASTORE_RW_DIR/users.json"
init_datastore_install > /dev/null
ok "users.json-only survivor fails the install" "$?" "1"
ok "surviving users.json is byte-identical" \
    "$(<"$SC_DATASTORE_RW_DIR/users.json")" '{"sentinel":{"role":"user"}}'
ok "no hosts.json was seeded over the survivor state" \
    "$([[ -e $SC_DATASTORE_RW_DIR/hosts.json ]] && echo no || echo yes)" "yes"
ok "survivor state is not blessed" \
    "$([[ -e $SC_DATASTORE_RW_DIR/.per-entity ]] && echo no || echo yes)" "yes"

echo "== real install path: users.json + containers.json survivors are preserved =="
SC_DATASTORE_RW_DIR="$TMP/ds-real-twojson"
SC_DATASTORE_RO_DIR="$TMP/ds-real-twojson-ro"
mkdir -p "$SC_DATASTORE_RW_DIR"
printf '{"sentinel":{"role":"user"}}\n' > "$SC_DATASTORE_RW_DIR/users.json"
printf '{"sentinelve":{"user":"sentinel"}}\n' > "$SC_DATASTORE_RW_DIR/containers.json"
init_datastore_install > /dev/null
ok "two-survivor store fails the install" "$?" "1"
ok "both survivors are byte-identical" \
    "$(<"$SC_DATASTORE_RW_DIR/users.json"):$(<"$SC_DATASTORE_RW_DIR/containers.json")" \
    '{"sentinel":{"role":"user"}}:{"sentinelve":{"user":"sentinel"}}'

echo "== real install path: surviving users/ entity dir is never seeded over =="
SC_DATASTORE_RW_DIR="$TMP/ds-real-usersdir"
SC_DATASTORE_RO_DIR="$TMP/ds-real-usersdir-ro"
mkdir -p "$SC_DATASTORE_RW_DIR/users"
printf '{"role":"user"}\n' > "$SC_DATASTORE_RW_DIR/users/sentinel.json"
init_datastore_install > /dev/null
ok "users-dir-only survivor fails the install" "$?" "1"
ok "surviving entity record is byte-identical" \
    "$(<"$SC_DATASTORE_RW_DIR/users/sentinel.json")" '{"role":"user"}'
ok "users-dir survivor is not blessed" \
    "$([[ -e $SC_DATASTORE_RW_DIR/.per-entity ]] && echo no || echo yes)" "yes"

echo "== real install path: hosts.json without the other monolithic files fails hard =="
SC_DATASTORE_RW_DIR="$TMP/ds-real-hostsjson"
SC_DATASTORE_RO_DIR="$TMP/ds-real-hostsjson-ro"
mkdir -p "$SC_DATASTORE_RW_DIR"
printf '{"h1.test":{"host_key":"k"}}\n' > "$SC_DATASTORE_RW_DIR/hosts.json"
install_rc=0
init_datastore_install > /dev/null 2>&1 || install_rc=$?
ok "hosts.json-only partial monolithic fails the install" \
    "$([[ $install_rc -ne 0 ]] && echo yes || echo no)" "yes"
ok "hosts.json survivor is byte-identical" \
    "$(<"$SC_DATASTORE_RW_DIR/hosts.json")" '{"h1.test":{"host_key":"k"}}'
ok "hosts.json-only partial monolithic is not blessed" \
    "$([[ -e $SC_DATASTORE_RW_DIR/.per-entity ]] && echo no || echo yes)" "yes"

echo "== real install path: complete marker-less restore is blessed =="
SC_DATASTORE_RW_DIR="$TMP/ds-real-complete"
SC_DATASTORE_RO_DIR="$TMP/ds-real-complete-ro"
mkdir -p "$SC_DATASTORE_RW_DIR/hosts" "$SC_DATASTORE_RW_DIR/users" "$SC_DATASTORE_RW_DIR/containers"
printf '{"host_key":"k"}\n' > "$SC_DATASTORE_RW_DIR/hosts/h1.test.json"
init_datastore_install > /dev/null
ok "complete restore succeeds through the real install" "$?" "0"
ok "complete restore is marked authoritative" \
    "$([[ -f $SC_DATASTORE_RW_DIR/.per-entity ]] && echo yes || echo no)" "yes"

echo "== init_datastore triggers install for a marker-less per-entity store =="
## The reconcile stub reproduces the production contract that exposed the
## bug: it fails 113 unless the .per-entity marker exists at reconcile time.
FAKE_INSTALL="$TMP/fake-install"
mkdir -p "$FAKE_INSTALL/modules/datastore/lib"
cat > "$FAKE_INSTALL/modules/datastore/lib/reconcile-hosts.mjs" << 'EOF'
import fs from "node:fs";
import path from "node:path";
const dir = process.argv[4];
if (!fs.existsSync(path.join(dir, ".per-entity"))) {
    console.error(`DATA-ERROR: HOST-TOPOLOGY datastore ${dir} is not an authoritative per-entity store`);
    process.exit(113);
}
EOF
SC_DATASTORE_RW_DIR="$TMP/ds-trigger"
SC_DATASTORE_RO_DIR="$TMP/ds-trigger-ro"
mkdir -p "$SC_DATASTORE_RW_DIR/hosts" "$SC_DATASTORE_RW_DIR/users" \
    "$SC_DATASTORE_RW_DIR/containers"
printf '{"host_key":"k"}\n' > "$SC_DATASTORE_RW_DIR/hosts/h1.json"
SC_INSTALL_DIR="$FAKE_INSTALL"
SC_DATASTORE_RO_USE=false
USER=root
INSTALL_CALLS=0
init_datastore_install() {
    INSTALL_CALLS=$((INSTALL_CALLS + 1))
    migrate_datastore_to_per_entity
}
exif() { local rc=$?; [[ $rc -eq 0 ]] || exit "$rc"; }
init_datastore
ok "init_datastore succeeds on a marker-less per-entity store" "$?" "0"
ok "install/migration was triggered" "$INSTALL_CALLS" "1"
ok "reconciliation ran against an authoritative store" \
    "$([[ -f $SC_DATASTORE_RW_DIR/.per-entity ]] && echo yes || echo no)" "yes"

echo "$pass passed, $fail failed"
[[ $fail == 0 ]]
