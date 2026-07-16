#!/bin/bash
#
# modules/containers/selftest/regenlib.test.sh — isolated cluster regenerate
# ordering and failure aggregation tests. All host commands are stubbed.
# Run: bash modules/containers/selftest/regenlib.test.sh

# Stubs and their environment are consumed indirectly by sourced production
# scripts, which shellcheck cannot resolve across this dynamic source boundary.
# SC2154 covers current_sha/current_hosts dynamically scoped by the real
# publication verifier into the manifest-reader double.
# shellcheck disable=SC2034,SC2329,SC2154
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

pass=0
fail=0
ok() {
    if [[ "$2" == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}

CANONICAL_HOST_ROWS=""
CANONICAL_HOSTS_RC=0
CANONICAL_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
CANONICAL_SHA_RC=0
SHA_DRIFT_HOST=""
SHA_READ_FAIL_HOST=""
SHA_INVALID_HOST=""
HOSTNAME=""
SC_CLUSTERNAME="test-cluster"
SC_INSTALL_BIN="/test/srvctl"
SC_INSTALL_DIR="$REPO"
TOPOLOGY_ROWS=""
TOPOLOGY_RC=0
TOPOLOGY_DRIFT_HOST=""
TOPOLOGY_HIDDEN_REPLICA_HOST=""
TOPOLOGY_READ_FAIL_HOST=""
PUBLICATION_MANIFEST_RC=0
PUBLICATION_SHA_OVERRIDE=""
PUBLICATION_HOST_OVERRIDE=0
PUBLICATION_HOST_ROWS=""
GET_CALLS=0
declare -A FAIL_HOST=()
declare -a EXECUTED=()
declare -a TRANSPORT=()
declare -a EXPECTED_SHAS=()
declare -a ERRORS=()

msg() { :; }
err() { ERRORS+=("$*"); }
get() {
    GET_CALLS=$((GET_CALLS + 1))
    return 99
}
run() {
    local host expected=""
    if [[ $1 == env ]] && [[ $3 == "$SC_INSTALL_BIN" ]]
    then
        host="$HOSTNAME"
        expected="${2#SC_EXPECTED_CLUSTERS_SHA256=}"
        TRANSPORT+=("local:$host")
    elif [[ $1 == ssh ]]
    then
        host="$6"
        expected="${7%% *}"
        expected="${expected#SC_EXPECTED_CLUSTERS_SHA256=}"
        TRANSPORT+=("remote:$host")
    else
        ERRORS+=("unexpected run invocation: $*")
        return 70
    fi
    EXECUTED+=("$host")
    EXPECTED_SHAS+=("$expected")
    return "${FAIL_HOST["$host"]:-0}"
}

# Load the real publication-inventory comparator before the all-host consumer;
# only its manifest reader is replaced below.
# shellcheck source=/dev/null
source "$REPO/modules/datastore/libs/datalib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/regenlib.sh"

_cluster_load_publication_manifest() {
    local sha host rows
    [[ $PUBLICATION_MANIFEST_RC -eq 0 ]] || return "$PUBLICATION_MANIFEST_RC"
    sha="${PUBLICATION_SHA_OVERRIDE:-$current_sha}"
    printf 'sha256\t%s\n' "$sha"
    if [[ $PUBLICATION_HOST_OVERRIDE -eq 1 ]]
    then
        rows="$PUBLICATION_HOST_ROWS"
        while IFS= read -r host
        do
            [[ -n $host ]] && printf 'host\t%s\n' "$host"
        done <<< "$rows"
    else
        for host in "${current_hosts[@]}"
        do
            printf 'host\t%s\n' "$host"
        done
    fi
}

_canonical_cluster_hosts() {
    [[ -n $CANONICAL_HOST_ROWS ]] && printf '%s\n' "$CANONICAL_HOST_ROWS"
    return "$CANONICAL_HOSTS_RC"
}
## Called via $( ) subshells, so the call counter must live in a file.
SHA_CALLS_FILE="$(mktemp)"
trap 'rm -f "$SHA_CALLS_FILE"' EXIT
_canonical_clusters_sha() {
    local calls=0
    [[ -s $SHA_CALLS_FILE ]] && calls="$(<"$SHA_CALLS_FILE")"
    calls=$((calls + 1))
    printf '%s' "$calls" > "$SHA_CALLS_FILE"
    ## Simulates a publication landing mid-run: after the configured number
    ## of reads the canonical file reports a different generation.
    if [[ -n $CANONICAL_SHA_FLIP_AFTER ]] && (( calls > CANONICAL_SHA_FLIP_AFTER ))
    then
        printf 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\n'
        return 0
    fi
    [[ -n $CANONICAL_SHA ]] && printf '%s\n' "$CANONICAL_SHA"
    return "$CANONICAL_SHA_RC"
}
_canonical_clusters_sha_on() {
    local host="$1"
    if [[ $host == "$SHA_READ_FAIL_HOST" ]]
    then
        return 45
    fi
    if [[ $host == "$SHA_INVALID_HOST" ]]
    then
        printf 'not-a-sha256\n'
    elif [[ $host == "$SHA_DRIFT_HOST" ]]
    then
        printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n'
    else
        printf '%s\n' "$CANONICAL_SHA"
    fi
    return 0
}

_dns_topology_hosts() {
    [[ -n $TOPOLOGY_ROWS ]] && printf '%s\n' "$TOPOLOGY_ROWS"
    return "$TOPOLOGY_RC"
}
_dns_topology_hosts_on() {
    local host="$1"
    if [[ $host == "$TOPOLOGY_READ_FAIL_HOST" ]]
    then
        return 44
    fi
    if [[ $host == "$TOPOLOGY_DRIFT_HOST" ]]
    then
        printf 'primary\tdifferent-primary\n'
    elif [[ $host == "$TOPOLOGY_HIDDEN_REPLICA_HOST" ]]
    then
        [[ -n $TOPOLOGY_ROWS ]] && printf '%s\n' "$TOPOLOGY_ROWS"
        printf 'replica\t%s\n' "$host"
    else
        [[ -n $TOPOLOGY_ROWS ]] && printf '%s\n' "$TOPOLOGY_ROWS"
    fi
    return 0
}

reset_probe() {
    CANONICAL_HOST_ROWS=""
    CANONICAL_HOSTS_RC=0
    CANONICAL_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    CANONICAL_SHA_RC=0
    CANONICAL_SHA_FLIP_AFTER=""
    : > "$SHA_CALLS_FILE"
    SHA_DRIFT_HOST=""
    SHA_READ_FAIL_HOST=""
    SHA_INVALID_HOST=""
    HOSTNAME=""
    TOPOLOGY_ROWS=""
    TOPOLOGY_RC=0
    TOPOLOGY_DRIFT_HOST=""
    TOPOLOGY_HIDDEN_REPLICA_HOST=""
    TOPOLOGY_READ_FAIL_HOST=""
    PUBLICATION_MANIFEST_RC=0
    PUBLICATION_SHA_OVERRIDE=""
    PUBLICATION_HOST_OVERRIDE=0
    PUBLICATION_HOST_ROWS=""
    GET_CALLS=0
    FAIL_HOST=()
    EXECUTED=()
    TRANSPORT=()
    EXPECTED_SHAS=()
    ERRORS=()
}

join() { local IFS=,; echo "$*"; }

echo "== role-aware ordering =="
reset_probe
CANONICAL_HOST_ROWS=$'replica1\nlegacy2\nordinary1\nprimary1\nordinary2\nordinary1\nreplica1'
HOSTNAME="replica1"
TOPOLOGY_ROWS=$'primary\tprimary1\nreplica\treplica1\nreplica\tlegacy2'
regenerate_all_hosts
rc=$?
ok "unique dns_primary wins" "$(join "${EXECUTED[@]}")" \
    "ordinary1,ordinary2,primary1,replica1,legacy2"
ok "local uses subprocess; remotes use ssh" "$(join "${TRANSPORT[@]}")" \
    "remote:ordinary1,remote:ordinary2,remote:primary1,local:replica1,remote:legacy2"
ok "every child receives the plan generation" "$(join "${EXPECTED_SHAS[@]}")" \
    "$CANONICAL_SHA,$CANONICAL_SHA,$CANONICAL_SHA,$CANONICAL_SHA,$CANONICAL_SHA"
ok "successful run returns zero" "$rc" "0"
ok "matching published inventory permits all-host regeneration" "$rc" "0"

echo "== mid-run publication guard =="
## Generation reads: 1 = initial checksum, 2 = post-preflight recheck,
## 3+ = the per-host probes before each execution.
reset_probe
CANONICAL_HOST_ROWS=$'local\nremote1\nremote2'
HOSTNAME=local
CANONICAL_SHA_FLIP_AFTER=2
if regenerate_all_hosts; then rc=0; else rc=$?; fi
ok "generation change right after preflight aborts" "$rc" "1"
ok "no host is contacted with the stale plan" "$(join "${EXECUTED[@]}")" ""

reset_probe
CANONICAL_HOST_ROWS=$'local\nremote1\nremote2'
HOSTNAME=local
CANONICAL_SHA_FLIP_AFTER=3
if regenerate_all_hosts; then rc=0; else rc=$?; fi
ok "mid-loop generation change aborts the remaining hosts" "$rc" "1"
ok "hosts after the change are not contacted" "$(join "${EXECUTED[@]}")" "local"

echo "== last-successful publication gate =="
reset_probe
CANONICAL_HOST_ROWS=$'local\nremaining'
HOSTNAME=local
PUBLICATION_HOST_OVERRIDE=1
PUBLICATION_HOST_ROWS=$'local\nremaining\nremoved-old-host'
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "canonical with an omitted published host runs no hosts" \
    "$(join "${EXECUTED[@]}")" ""
ok "removed-host bypass fails closed" "$rc" "1"
ok "removed-host bypass directs operator through publication" "${ERRORS[-1]}" \
    "Canonical cluster topology is not the last successful publication; run publish_data first"

reset_probe
CANONICAL_HOST_ROWS=$'local\nremaining'
HOSTNAME=local
PUBLICATION_SHA_OVERRIDE="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "canonical SHA newer than publication runs no hosts" \
    "$(join "${EXECUTED[@]}")" ""
ok "publication SHA mismatch fails closed" "$rc" "1"
ok "SHA mismatch directs operator through publication" "${ERRORS[-1]}" \
    "Canonical cluster topology is not the last successful publication; run publish_data first"

reset_probe
CANONICAL_HOST_ROWS=$'local\nremaining'
HOSTNAME=local
PUBLICATION_MANIFEST_RC=100
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "absent publication manifest runs no hosts" "$(join "${EXECUTED[@]}")" ""
ok "absent publication manifest fails closed" "$rc" "1"

reset_probe
CANONICAL_HOST_ROWS=$'local\nremaining'
HOSTNAME=local
PUBLICATION_MANIFEST_RC=113
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "invalid publication manifest runs no hosts" "$(join "${EXECUTED[@]}")" ""
ok "invalid publication manifest fails closed" "$rc" "1"

echo "== invalid global topology =="
reset_probe
CANONICAL_HOST_ROWS=$'slave1\nmaster2\nordinary\nmaster1'
HOSTNAME="ordinary"
TOPOLOGY_RC=111
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "invalid topology runs no hosts" "$(join "${EXECUTED[@]}")" ""
ok "invalid topology preserves helper status" "$rc" "111"

echo "== topology agreement before mutation =="
reset_probe
CANONICAL_HOST_ROWS=$'ordinary\nprimary\nreplica'
HOSTNAME="ordinary"
TOPOLOGY_ROWS=$'primary\tprimary\nreplica\treplica'
TOPOLOGY_DRIFT_HOST=replica
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "topology drift runs no hosts" "$(join "${EXECUTED[@]}")" ""
ok "topology drift fails closed" "$rc" "1"
ok "topology drift names the host" "${ERRORS[-1]}" \
    "DNS topology mismatch on host replica; synchronize /etc/srvctl/clusters.json"

reset_probe
CANONICAL_HOST_ROWS=$'r2\nbp\napplication'
HOSTNAME="r2"
TOPOLOGY_ROWS=$'primary\tr2'
TOPOLOGY_HIDDEN_REPLICA_HOST=bp
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "locally omitted replica runs no hosts" "$(join "${EXECUTED[@]}")" ""
ok "locally omitted replica fails closed" "$rc" "1"
ok "locally omitted replica names ordinary host" "${ERRORS[-1]}" \
    "DNS topology mismatch on host bp; synchronize /etc/srvctl/clusters.json"

reset_probe
CANONICAL_HOST_ROWS=$'ordinary\nprimary\nreplica'
HOSTNAME="ordinary"
TOPOLOGY_ROWS=$'primary\tprimary\nreplica\treplica'
TOPOLOGY_READ_FAIL_HOST=primary
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "unverifiable topology runs no hosts" "$(join "${EXECUTED[@]}")" ""
ok "topology read preserves status" "$rc" "44"

echo "== complete canonical file agreement before mutation =="
reset_probe
CANONICAL_HOST_ROWS=$'ordinary\nother-cluster-app\nprimary\nreplica'
HOSTNAME="ordinary"
TOPOLOGY_ROWS=$'primary\tprimary\nreplica\treplica'
SHA_DRIFT_HOST=other-cluster-app
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "same DNS election with different full file runs no hosts" \
    "$(join "${EXECUTED[@]}")" ""
ok "full-file checksum drift fails closed" "$rc" "1"
ok "checksum drift names the cross-cluster host" "${ERRORS[-1]}" \
    "Cluster configuration mismatch on host other-cluster-app; synchronize /etc/srvctl/clusters.json"

reset_probe
CANONICAL_HOST_ROWS=$'ordinary\nprimary\nreplica'
HOSTNAME="ordinary"
TOPOLOGY_ROWS=$'primary\tprimary\nreplica\treplica'
SHA_READ_FAIL_HOST=primary
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "unreadable remote canonical file runs no hosts" "$(join "${EXECUTED[@]}")" ""
ok "checksum read failure preserves status" "$rc" "45"
ok "checksum read failure names the host" "${ERRORS[-1]}" \
    "Cannot verify cluster configuration checksum on host primary"

reset_probe
CANONICAL_HOST_ROWS=$'ordinary\nprimary'
HOSTNAME="ordinary"
TOPOLOGY_ROWS=$'primary\tprimary'
SHA_INVALID_HOST=primary
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "malformed remote checksum runs no hosts" "$(join "${EXECUTED[@]}")" ""
ok "malformed remote checksum fails closed" "$rc" "1"

echo "== every cluster participates in global ordering =="
reset_probe
CANONICAL_HOST_ROWS=$'ordinary\nlocal-app\nother-cluster-app\nglobal-primary\nglobal-replica'
HOSTNAME="ordinary"
TOPOLOGY_ROWS=$'primary\tglobal-primary\nreplica\tglobal-replica'
regenerate_all_hosts
rc=$?
ok "cross-cluster ordinary hosts precede global DNS roles" "$(join "${EXECUTED[@]}")" \
    "ordinary,local-app,other-cluster-app,global-primary,global-replica"
ok "cross-cluster ordering succeeds" "$rc" "0"
ok "orchestration never reads stale datastore host_list" "$GET_CALLS" "0"

echo "== installation without DNS roles =="
reset_probe
CANONICAL_HOST_ROWS=$'ordinary\nlocal-app'
HOSTNAME="ordinary"
regenerate_all_hosts
rc=$?
ok "no-DNS installation regenerates ordinary hosts" "$(join "${EXECUTED[@]}")" \
    "ordinary,local-app"
ok "no-DNS ordering succeeds" "$rc" "0"

echo "== failure aggregation =="
reset_probe
CANONICAL_HOST_ROWS=$'remote-ordinary\nlocal-primary\nremote-replica'
HOSTNAME="local-primary"
TOPOLOGY_ROWS=$'primary\tlocal-primary\nreplica\tremote-replica'
FAIL_HOST[remote-ordinary]=9
FAIL_HOST[local-primary]=8
FAIL_HOST[remote-replica]=7
if regenerate_all_hosts
then
    rc=0
else
    rc=$?
fi
ok "all hosts still attempted" "$(join "${EXECUTED[@]}")" \
    "remote-ordinary,local-primary,remote-replica"
ok "aggregate returns nonzero" "$rc" "1"
ok "aggregate names every failed host" "${ERRORS[-1]}" \
    "Regeneration failed on hosts: remote-ordinary local-primary remote-replica"

echo "== command status propagation =="
probe_command_status() {
    root_only() { :; }
    hs_only() { :; }
    regenerate_all_hosts() { return 23; }
    msg() { :; }
    ARG=all-hosts
    SRVCTL=1
    # shellcheck source=/dev/null
    source "$REPO/modules/containers/commands/regenerate.sh"
}
if probe_command_status
then
    rc=0
else
    rc=$?
fi
ok "final msg does not mask aggregate status" "$rc" "23"

echo ""
echo "regenlib.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
