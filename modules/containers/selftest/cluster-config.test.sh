#!/bin/bash
# Isolated canonical cluster configuration pipeline tests.
# Variables are consumed indirectly by the sourced production helper.
# shellcheck disable=SC2034,SC2329

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SC_INSTALL_DIR="$REPO"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

SC_CLUSTER_CONFIG_NODE=/bin/node
SC_CLUSTER_CONFIG_CLI="$REPO/modules/containers/lib/cluster-config-cli.js"
SC_CLUSTER_CONFIG_LOCK_FILE="$tmp/lock"
SC_CLUSTER_CONFIG_ETC_ROOT="$tmp/etc/srvctl"
SC_CLUSTER_CONFIG_VAR_ROOT="$tmp/var/srvctl3"
SC_CLUSTER_CONFIG_LOCAL_ROOT="$tmp/var/local/srvctl"
SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE="$tmp/root/.srvctl/modules.conf"

# shellcheck source=/dev/null
source "$REPO/modules/containers/lib/cluster-config.sh"

pass=0 fail=0
ok() {
    if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else
        fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"
    fi
}
fails113() {
    if "$@" >/dev/null 2>&1; then echo 0; else echo "$?"; fi
}

host="$(hostname)"
write_config() {
    local path="$1" role="${2:-master}" hostname="${3:-$host}"
    mkdir -p "$(dirname "$path")"
    printf '{"farm":{"%s":{"hostnet":40,"dns_server":"%s"}}}\n' "$hostname" "$role" > "$path"
}
new_case() {
    case_root="$tmp/$1"
    canonical="$case_root/etc/srvctl/clusters.json"
    legacy="$case_root/etc/srvctl/data/clusters.json"
    host_conf="$case_root/var/srvctl3/host/host.conf"
    hosts_file="$case_root/var/srvctl3/host/hosts.json"
    mkdir -p "$case_root/etc/srvctl/data" "$case_root/var/srvctl3" "$case_root/var/local/srvctl"
    SC_CLUSTER_CONFIG_LOCK_FILE="$case_root/run/cluster.lock"
    SC_CLUSTER_CONFIG_HOST_DIR="$case_root/var/srvctl3/host"
    SC_CLUSTER_CONFIG_LEGACY_HOST_CONF="$case_root/etc/srvctl/host.conf"
    SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE="$case_root/etc/srvctl/hosts.json"
    SC_CLUSTER_CONFIG_ETC_ROOT="$case_root/etc/srvctl"
    SC_CLUSTER_CONFIG_VAR_ROOT="$case_root/var/srvctl3"
    SC_CLUSTER_CONFIG_LOCAL_ROOT="$case_root/var/local/srvctl"
    SC_CLUSTER_CONFIG_RETIRE_MARKER="$case_root/var/srvctl3/cluster-config/retired-generation.sha256"
    SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE="$case_root/var/local/srvctl/modules.conf"
    SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE="$case_root/root/.srvctl/modules.conf"
}

echo "== migration validates before mutation =="
new_case legacy-only
write_config "$legacy"
chmod 600 "$legacy"
inode="$(stat -c %i "$legacy")"
migrate_legacy_clusters_config "$canonical" "$legacy"
ok "legacy moved" "$([[ -f $canonical && ! -e $legacy ]] && echo yes || echo no)" yes
ok "migration uses rename" "$(stat -c %i "$canonical")" "$inode"
ok "canonical mode" "$(stat -c %a "$canonical")" 644

new_case identical
write_config "$canonical"; cp "$canonical" "$legacy"; chmod 600 "$canonical"
migrate_legacy_clusters_config "$canonical" "$legacy"
ok "identical legacy removed" "$([[ ! -e $legacy ]] && echo yes || echo no)" yes
ok "kept canonical mode" "$(stat -c %a "$canonical")" 644

new_case divergent
write_config "$canonical" master; write_config "$legacy" slave
ok "divergent fails" "$(fails113 migrate_legacy_clusters_config "$canonical" "$legacy")" 113
ok "divergent preserves both" "$([[ -f $canonical && -f $legacy ]] && echo yes || echo no)" yes

new_case malformed
printf 'not json\n' > "$legacy"
ok "malformed legacy fails" "$(fails113 migrate_legacy_clusters_config "$canonical" "$legacy")" 113
ok "malformed legacy not moved" "$([[ -f $legacy && ! -e $canonical ]] && echo yes || echo no)" yes

new_case malformed-identical
printf 'not json\n' > "$canonical"; cp "$canonical" "$legacy"
ok "invalid identical pair fails before delete" "$(fails113 migrate_legacy_clusters_config "$canonical" "$legacy")" 113
ok "invalid identical pair preserved" "$([[ -f $canonical && -f $legacy ]] && echo yes || echo no)" yes

new_case unknown-legacy
write_config "$legacy" master other.test
ok "unknown local legacy fails before move" \
    "$(fails113 migrate_legacy_clusters_config "$canonical" "$legacy")" 113
ok "unknown local legacy is preserved" \
    "$([[ -f $legacy && ! -e $canonical ]] && echo yes || echo no)" yes

new_case dangling-symlink
ln -s "$case_root/missing.json" "$legacy"
ok "dangling legacy symlink fails closed" \
    "$(fails113 migrate_legacy_clusters_config "$canonical" "$legacy")" 113
ok "dangling symlink is not mutated" "$([[ -L $legacy ]] && echo yes || echo no)" yes

new_case canonical-only
write_config "$canonical"; chmod 600 "$canonical"
migrate_legacy_clusters_config "$canonical" "$legacy"
ok "canonical-only normalized" "$(stat -c %a "$canonical")" 644

echo "== shared schema and CLI =="
new_case schema
printf '[]\n' > "$canonical"
ok "root array rejected" "$(fails113 _cluster_config_cli validate "$canonical")" 113
printf '{"farm":[]}\n' > "$canonical"
ok "host-map array rejected" "$(fails113 _cluster_config_cli validate "$canonical")" 113
printf '{"farm":{"node.test":[]}}\n' > "$canonical"
ok "host config array rejected" "$(fails113 _cluster_config_cli validate "$canonical")" 113
printf '{"one":{"same.test":{}},"two":{"same.test":{}}}\n' > "$canonical"
ok "duplicate hostname rejected" "$(fails113 _cluster_config_cli validate "$canonical")" 113
printf '{"bad name":{"node.test":{}}}\n' > "$canonical"
ok "unsafe cluster name rejected" "$(fails113 _cluster_config_cli validate "$canonical")" 113
printf '{"farm":{"BAD HOST":{}}}\n' > "$canonical"
ok "unsafe hostname rejected" "$(fails113 _cluster_config_cli validate "$canonical")" 113
printf '{"farm":{"node.test":{"bad-key":"x"}}}\n' > "$canonical"
ok "unsafe shell key rejected" "$(fails113 _cluster_config_cli validate "$canonical")" 113
write_config "$canonical"
sha="$(_cluster_config_cli sha256 "$canonical")"
ok "sha output" "$([[ $sha =~ ^[0-9a-f]{64}$ ]] && echo yes || echo no)" yes
ok "hosts output" "$(_cluster_config_cli hosts "$canonical")" "$host"
ok "capability" "$(cluster_config_capability)" srvctl-cluster-config-v2

echo "== strict atomic projections =="
new_case projections
write_config "$canonical"
refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file"
ok "projection verifies" "$(fails113 _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file")" 0
ok "canonical hash embedded" "$([[ $(<"$host_conf") == *"SC_CLUSTERS_SHA256="* ]] && echo yes || echo no)" yes
ok "hosts hash embedded" "$([[ $(<"$host_conf") == *"SC_HOSTS_SHA256="* ]] && echo yes || echo no)" yes
ok "projection modes" "$(stat -c %a "$host_conf"):$(stat -c %a "$hosts_file")" "644:644"
ok "no temporary outputs" "$(find "$case_root/etc/srvctl" "$case_root/var/srvctl3/host" -maxdepth 1 -name '*.tmp.*' -print -quit)" ""
ok "host projection dir is world-traversable" "$(stat -c %a "$case_root/var/srvctl3/host")" 755

printf 'old-host-conf\n' > "$host_conf"; printf 'old-hosts\n' > "$hosts_file"
write_config "$canonical" master other.test
ok "unknown local host rejected" "$(fails113 refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file")" 113
ok "unknown host preserves host.conf" "$(<"$host_conf")" old-host-conf
ok "unknown host preserves hosts.json" "$(<"$hosts_file")" old-hosts

new_case quoting
node - "$canonical" "$host" "$case_root/pwned" <<'NODE'
const fs = require("fs");
fs.writeFileSync(process.argv[2], JSON.stringify({farm: {[process.argv[3]]: {
  label: "hello world ' $(touch " + process.argv[4] + ")"
}}}));
NODE
refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file"
quoted_value="$(bash -c 'source "$1"; printf "%s" "$SC_LABEL"' _ "$host_conf")"
ok "scalar shell quoting" "$quoted_value" "hello world ' \$(touch $case_root/pwned)"
ok "quoted value not executed" "$([[ -e $case_root/pwned ]] && echo no || echo yes)" yes

echo "== validated first-hostname bootstrap =="
new_case hostname-bootstrap
intended=first-host.test
write_config "$legacy" master "$intended"
mkdir -p "$(dirname "$SC_CLUSTER_CONFIG_RETIRE_MARKER")" \
    "$(dirname "$SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE")" \
    "$(dirname "$SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE")"
printf '%064d\n' 0 > "$SC_CLUSTER_CONFIG_RETIRE_MARKER"
printf stale > "$SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE"
printf stale > "$SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE"
bootstrap_sha="$(prepare_cluster_hostname_bootstrap "$intended" \
    "$canonical" "$legacy" "$host_conf" "$hosts_file")"
ok "bootstrap promotes legacy canonical" \
    "$([[ -f $canonical && ! -e $legacy ]] && echo yes || echo no)" yes
ok "bootstrap returns canonical hash" "$bootstrap_sha" \
    "$(_cluster_config_cli sha256 "$canonical")"
ok "bootstrap renders intended hostname" \
    "$(bash -c 'source "$1"; printf "%s" "$SC_HOSTNAME"' _ "$host_conf")" "$intended"
ok "bootstrap projection verifies as intended host" \
    "$(fails113 _cluster_config_cli verify "$canonical" "$host_conf" \
        "$hosts_file" "$intended")" 0
ok "explicit hostname enrollment clears retirement marker" \
    "$([[ ! -e $SC_CLUSTER_CONFIG_RETIRE_MARKER ]] && echo yes || echo no)" yes
ok "explicit hostname enrollment invalidates module caches" \
    "$([[ ! -e $SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE && ! -e $SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE ]] && echo yes || echo no)" yes

new_case hostname-bootstrap-invalid-marker
write_config "$legacy" master "$intended"
mkdir -p "$(dirname "$SC_CLUSTER_CONFIG_RETIRE_MARKER")"
ln -s "$case_root/missing-marker" "$SC_CLUSTER_CONFIG_RETIRE_MARKER"
ok "invalid retirement marker blocks hostname enrollment" \
    "$(fails113 prepare_cluster_hostname_bootstrap "$intended" \
        "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
ok "blocked hostname enrollment preserves legacy topology" \
    "$([[ -f $legacy && ! -e $canonical ]] && echo yes || echo no)" yes

new_case hostname-bootstrap-reject
write_config "$legacy" master "$intended"
mkdir -p "$(dirname "$host_conf")"
printf 'old-host-conf\n' > "$host_conf"
printf 'old-hosts\n' > "$hosts_file"
ok "unknown intended bootstrap host rejected" \
    "$(fails113 prepare_cluster_hostname_bootstrap unknown.test \
        "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
ok "rejected bootstrap preserves legacy source" \
    "$([[ -f $legacy && ! -e $canonical ]] && echo yes || echo no)" yes
ok "rejected bootstrap preserves projections" \
    "$(<"$host_conf"):$(<"$hosts_file")" "old-host-conf:old-hosts"

condition_file="$REPO/modules/containers/module-condition.sh"
bootstrap_condition="$(
    HOSTNAME=localhost.localdomain
    CMD=update-install
    ARG="$intended"
    SC_CLUSTER_HOSTNAME_BOOTSTRAP=true
    SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME="$intended"
    # shellcheck source=modules/containers/module-condition.sh
    source "$condition_file"
)"
raw_condition="$(
    HOSTNAME=localhost.localdomain
    CMD=update-install
    ARG="$intended"
    SC_CLUSTER_HOSTNAME_BOOTSTRAP=false
    SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME=
    # shellcheck source=modules/containers/module-condition.sh
    source "$condition_file"
)"
ok "validated bootstrap enables containers" "$bootstrap_condition" true
ok "raw update argument cannot bypass validation" "$raw_condition" false

echo "== locked audit, stale and disappearance checks =="
new_case no-lock
ok "fresh non-farm without lock is valid" \
    "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 0
write_config "$canonical"
ok "configured nonroot requires initialized lock" \
    "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113

new_case stale
write_config "$canonical" master
reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file" >/dev/null
ok "fresh nonroot projection accepted" "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 0
write_config "$canonical" slave
ok "stale projection rejected" "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file" >/dev/null
printf 'corrupt\n' > "$hosts_file"
ok "corrupt hosts projection rejected" "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113

rm -f "$canonical"
ok "canonical disappearance rejected" "$(fails113 reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
rm -f "$host_conf" "$hosts_file"
ok "fresh non-farm remains valid" "$(fails113 reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file")" 0

echo "== legacy /etc projection migration =="
new_case legacy-projection
write_config "$canonical"
printf 'stale-legacy-conf\n' > "$SC_CLUSTER_CONFIG_LEGACY_HOST_CONF"
printf 'stale-legacy-hosts\n' > "$SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE"
reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file" >/dev/null
ok "reconcile renders projections in the host dir" \
    "$(fails113 _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file")" 0
ok "reconcile removes the legacy /etc projections" \
    "$([[ ! -e $SC_CLUSTER_CONFIG_LEGACY_HOST_CONF && ! -e $SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE ]] && echo yes || echo no)" yes
printf 'stale-legacy-conf\n' > "$SC_CLUSTER_CONFIG_LEGACY_HOST_CONF"
ok "nonroot rejects a lingering legacy projection" \
    "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
rm -f "$SC_CLUSTER_CONFIG_LEGACY_HOST_CONF"
ok "nonroot accepts once the legacy projection is migrated" \
    "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 0

new_case legacy-projection-only
printf 'stale-legacy-conf\n' > "$SC_CLUSTER_CONFIG_LEGACY_HOST_CONF"
ok "canonical absent with legacy projection fails closed" \
    "$(fails113 reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
ok "nonroot without lock rejects legacy-only projection" \
    "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113

echo "== projection directory hygiene =="
new_case dir-normalize
write_config "$canonical"
mkdir -p "$SC_CLUSTER_CONFIG_HOST_DIR"
chmod 777 "$SC_CLUSTER_CONFIG_HOST_DIR"
refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file"
ok "existing projection dir is normalized to 0755" \
    "$(stat -c %a "$SC_CLUSTER_CONFIG_HOST_DIR")" 755
chmod 700 "$SC_CLUSTER_CONFIG_HOST_DIR"
refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file"
ok "locked-down projection dir is reopened to 0755" \
    "$(stat -c %a "$SC_CLUSTER_CONFIG_HOST_DIR")" 755

new_case dir-symlink
write_config "$canonical"
mkdir -p "$case_root/elsewhere"
ln -s "$case_root/elsewhere" "$SC_CLUSTER_CONFIG_HOST_DIR"
ok "symlinked projection dir fails closed" \
    "$(fails113 refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file")" 113
ok "symlinked projection dir receives no files" \
    "$(find "$case_root/elsewhere" -type f -print -quit)" ""

echo "== raw-byte generation probe =="
new_case generation-probe
write_config "$canonical"
reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file" >/dev/null
canonical_sha="$(_cluster_config_cli sha256 "$canonical")"
ok "sha256sum matches the CLI canonical hash" \
    "$(sha256sum -- "$canonical" | cut -d' ' -f1)" "$canonical_sha"
probe_hosts_sha="$(bash -c 'source "$1"; printf "%s" "$SC_HOSTS_SHA256"' _ "$host_conf")"
ok "sha256sum matches the embedded hosts hash" \
    "$(sha256sum -- "$hosts_file" | cut -d' ' -f1)" "$probe_hosts_sha"
ok "probe accepts the coherent generation" \
    "$(cluster_generation_matches "$canonical_sha" "$probe_hosts_sha" "$canonical" "$hosts_file" && echo yes || echo no)" yes
write_config "$canonical" slave
ok "probe detects a replaced canonical" \
    "$(cluster_generation_matches "$canonical_sha" "$probe_hosts_sha" "$canonical" "$hosts_file" && echo yes || echo no)" no
write_config "$canonical"
printf '\n' >> "$hosts_file"
ok "probe detects a replaced hosts projection" \
    "$(cluster_generation_matches "$canonical_sha" "$probe_hosts_sha" "$canonical" "$hosts_file" && echo yes || echo no)" no

echo "== documented v3 rollback =="
new_case rollback
write_config "$canonical"
reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file" >/dev/null
rollback_sha="$(prepare_cluster_rollback_to_legacy "$canonical" "$legacy")"
ok "rollback returns the canonical generation" \
    "$rollback_sha" "$(_cluster_config_cli sha256 "$canonical")"
ok "rollback renders verifying legacy projections" \
    "$(fails113 _cluster_config_cli verify "$canonical" \
        "$SC_CLUSTER_CONFIG_LEGACY_HOST_CONF" "$SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE")" 0
ok "rollback restores the v3 update-install seed" \
    "$(cmp --silent -- "$canonical" "$legacy" && echo yes || echo no)" yes
ok "rollback keeps the live projections intact" \
    "$(fails113 _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file")" 0
ok "no rollback temporaries remain" \
    "$(find "$(dirname "$legacy")" -name '.clusters.json.rollback.*' -print -quit)" ""
reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file" >/dev/null
ok "forward re-upgrade migrates the rollback files away" \
    "$([[ ! -e $legacy && ! -e $SC_CLUSTER_CONFIG_LEGACY_HOST_CONF && ! -e $SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE ]] && echo yes || echo no)" yes

new_case rollback-requires-canonical
ok "rollback without canonical fails closed" \
    "$(fails113 prepare_cluster_rollback_to_legacy "$canonical" "$legacy")" 113

new_case rollback-v3-unsafe
node - "$canonical" "$host" <<'NODE'
const fs = require("fs");
fs.writeFileSync(process.argv[2], JSON.stringify({farm: {[process.argv[3]]: {
  hostnet: 40, label: "hello world"
}}}));
NODE
reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file" >/dev/null
ok "v4 keeps accepting a space-bearing value" \
    "$(fails113 _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file")" 0
ok "rollback refuses a value v3 renders unquoted" \
    "$(fails113 prepare_cluster_rollback_to_legacy "$canonical" "$legacy")" 113
ok "refused rollback writes no legacy files" \
    "$([[ ! -e $SC_CLUSTER_CONFIG_LEGACY_HOST_CONF && ! -e $SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE && ! -e $legacy ]] && echo yes || echo no)" yes

new_case rollback-v3-injection
node - "$canonical" "$host" "$case_root/pwned" <<'NODE'
const fs = require("fs");
fs.writeFileSync(process.argv[2], JSON.stringify({farm: {[process.argv[3]]: {
  hostnet: 40, label: "$(touch " + process.argv[4] + ")"
}}}));
NODE
ok "rollback refuses a command-substitution value" \
    "$(fails113 prepare_cluster_rollback_to_legacy "$canonical" "$legacy")" 113
ok "refused injection value never executes" \
    "$([[ -e $case_root/pwned ]] && echo no || echo yes)" yes
ok "v3safe passes a conservative topology" \
    "$(write_config "$canonical"; fails113 _cluster_config_cli v3safe "$canonical")" 0

new_case duplicates
write_config "$canonical"
mkdir -p "$SC_CLUSTER_CONFIG_VAR_ROOT/nested"
cp "$canonical" "$SC_CLUSTER_CONFIG_VAR_ROOT/nested/clusters.json"
ok "var duplicate rejected" "$(fails113 reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
ok "nonroot audit rejects var duplicate" \
    "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
rm -f "$SC_CLUSTER_CONFIG_VAR_ROOT/nested/clusters.json"
mkdir -p "$SC_CLUSTER_CONFIG_VAR_ROOT/rootfs/deep"
cp "$canonical" "$SC_CLUSTER_CONFIG_VAR_ROOT/rootfs/deep/clusters.json"
ok "audit prunes container rootfs" \
    "$(fails113 audit_cluster_config_paths "$canonical" "$legacy")" 0
rm -rf "$SC_CLUSTER_CONFIG_VAR_ROOT/rootfs"
mkdir -p "$SC_CLUSTER_CONFIG_VAR_ROOT/gluster/srvctl-data"
cp "$canonical" "$SC_CLUSTER_CONFIG_VAR_ROOT/gluster/srvctl-data/clusters.json"
ok "cheap audit checks pruned gluster datastore candidate" \
    "$(fails113 audit_cluster_config_paths "$canonical" "$legacy")" 113
rm -rf "$SC_CLUSTER_CONFIG_VAR_ROOT/gluster"
mkdir -p "$SC_CLUSTER_CONFIG_LOCAL_ROOT/nested"
cp "$canonical" "$SC_CLUSTER_CONFIG_LOCAL_ROOT/nested/clusters.json"
ok "var-local duplicate rejected" \
    "$(fails113 reconcile_cluster_config "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
rm -f "$SC_CLUSTER_CONFIG_LOCAL_ROOT/nested/clusters.json"
mkdir -p "$SC_CLUSTER_CONFIG_ETC_ROOT/unexpected"
cp "$canonical" "$SC_CLUSTER_CONFIG_ETC_ROOT/unexpected/clusters.json"
ok "nested etc duplicate rejected" "$(fails113 verify_cluster_projection_nonroot "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113

permission_audit_rc="$(
    find() { return 1; }
    if audit_cluster_config_paths "$canonical" "$legacy" \
        "$SC_CLUSTER_CONFIG_ETC_ROOT" "$SC_CLUSTER_CONFIG_VAR_ROOT" \
        "$SC_CLUSTER_CONFIG_LOCAL_ROOT" nonroot >/dev/null 2>&1
    then echo 0; else echo "$?"; fi
)"
ok "nonroot audit tolerates inaccessible subdirectories" "$permission_audit_rc" 0

echo "== prepared two-phase apply =="
new_case apply
write_config "$canonical" master
refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file"
old_canonical_sha="$(_cluster_config_cli sha256 "$canonical")"
prepared="$case_root/etc/srvctl/.clusters.json.prepared"
write_config "$prepared" slave
cp "$canonical" "$legacy"
expected="$(_cluster_config_cli sha256 "$prepared")"
mkdir -p "$(dirname "$SC_CLUSTER_CONFIG_RETIRE_MARKER")" \
    "$(dirname "$SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE")" \
    "$(dirname "$SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE")"
printf '%064d\n' 0 > "$SC_CLUSTER_CONFIG_RETIRE_MARKER"
printf stale > "$SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE"
printf stale > "$SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE"
ok "prepared validation" "$(fails113 validate_prepared_cluster_config "$prepared" "$expected" "$canonical" "$legacy" "$host_conf" "$hosts_file")" 0
apply_prepared_cluster_config "$prepared" "$expected" "$canonical" "$legacy" "$host_conf" "$hosts_file"
ok "prepared committed" "$(_cluster_config_cli sha256 "$canonical")" "$expected"
ok "identical legacy removed on commit" "$([[ ! -e $legacy ]] && echo yes || echo no)" yes
ok "committed projections verify" "$(fails113 _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file")" 0
ok "successful enrollment clears retirement marker" \
    "$([[ ! -e $SC_CLUSTER_CONFIG_RETIRE_MARKER ]] && echo yes || echo no)" yes
ok "successful enrollment invalidates module caches" \
    "$([[ ! -e $SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE && ! -e $SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE ]] && echo yes || echo no)" yes

prepared="$case_root/etc/srvctl/.clusters.json.divergent"
write_config "$prepared" master
write_config "$legacy" master
expected="$(_cluster_config_cli sha256 "$prepared")"
ok "divergent legacy blocks prepare" "$(fails113 validate_prepared_cluster_config "$prepared" "$expected" "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
ok "blocked prepared file preserved" "$([[ -f $prepared ]] && echo yes || echo no)" yes

new_case legacy-apply
prepared="$case_root/etc/srvctl/.clusters.json.prepared"
write_config "$prepared" master
cp "$prepared" "$legacy"
expected="$(_cluster_config_cli sha256 "$prepared")"
apply_prepared_cluster_config "$prepared" "$expected" "$canonical" "$legacy" "$host_conf" "$hosts_file"
ok "legacy-only apply promotes canonical" "$(_cluster_config_cli sha256 "$canonical")" "$expected"
ok "legacy-only apply removes both old paths" \
    "$([[ ! -e $legacy && ! -e $prepared ]] && echo yes || echo no)" yes
ok "legacy-only projections verify" \
    "$(fails113 _cluster_config_cli verify "$canonical" "$host_conf" "$hosts_file")" 0

echo "== exact-generation retirement =="
new_case retire
write_config "$canonical" master
refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file"
cp "$canonical" "$legacy"
printf 'stale-legacy-conf\n' > "$SC_CLUSTER_CONFIG_LEGACY_HOST_CONF"
mkdir -p "$(dirname "$SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE")" \
    "$(dirname "$SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE")"
printf stale > "$SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE"
printf stale > "$SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE"
expected="$(_cluster_config_cli sha256 "$canonical")"
ok "retirement returns exact generation" \
    "$(retire_cluster_config "$expected" "$canonical" "$legacy" "$host_conf" "$hosts_file")" "$expected"
ok "retirement removes topology and projections" \
    "$([[ ! -e $canonical && ! -e $legacy && ! -e $host_conf && ! -e $hosts_file ]] && echo yes || echo no)" yes
ok "retirement removes legacy /etc projections" \
    "$([[ ! -e $SC_CLUSTER_CONFIG_LEGACY_HOST_CONF && ! -e $SC_CLUSTER_CONFIG_LEGACY_HOSTS_FILE ]] && echo yes || echo no)" yes
ok "retirement invalidates module caches" \
    "$([[ ! -e $SC_CLUSTER_CONFIG_SYSTEM_MODULE_CACHE && ! -e $SC_CLUSTER_CONFIG_ROOT_MODULE_CACHE ]] && echo yes || echo no)" yes
ok "retirement marker records only SHA" "$(<"$SC_CLUSTER_CONFIG_RETIRE_MARKER")" "$expected"
ok "same-generation retirement retry succeeds" \
    "$(retire_cluster_config "$expected" "$canonical" "$legacy" "$host_conf" "$hosts_file")" "$expected"
wrong="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
ok "different-generation retry fails closed" \
    "$(fails113 retire_cluster_config "$wrong" "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113

new_case retire-wrong-generation
write_config "$canonical" master
refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file"
expected="$(_cluster_config_cli sha256 "$canonical")"
ok "wrong expected SHA does not retire" \
    "$(fails113 retire_cluster_config "$wrong" "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
ok "wrong expected SHA preserves canonical" "$(_cluster_config_cli sha256 "$canonical")" "$expected"

new_case retire-interrupted
write_config "$canonical" master
refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file"
expected="$(_cluster_config_cli sha256 "$canonical")"
mkdir -p "$(dirname "$SC_CLUSTER_CONFIG_RETIRE_MARKER")"
printf '%s\n' "$expected" > "$SC_CLUSTER_CONFIG_RETIRE_MARKER"
rm -f "$host_conf"
ok "matching marker resumes interrupted cleanup" \
    "$(retire_cluster_config "$expected" "$canonical" "$legacy" "$host_conf" "$hosts_file")" "$expected"
ok "resumed retirement removes remaining canonical" \
    "$([[ ! -e $canonical && ! -e $hosts_file ]] && echo yes || echo no)" yes

new_case retire-no-proof
ok "absent topology without marker cannot be blessed retired" \
    "$(fails113 retire_cluster_config "$wrong" "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113

new_case retire-marker-symlink
write_config "$canonical" master
refresh_cluster_host_config "$canonical" "$host_conf" "$hosts_file"
old_canonical_sha="$(_cluster_config_cli sha256 "$canonical")"
prepared="$case_root/etc/srvctl/.clusters.json.prepared"
write_config "$prepared" slave
expected="$(_cluster_config_cli sha256 "$prepared")"
mkdir -p "$(dirname "$SC_CLUSTER_CONFIG_RETIRE_MARKER")"
ln -s "$case_root/missing-marker" "$SC_CLUSTER_CONFIG_RETIRE_MARKER"
ok "invalid retirement marker blocks apply before mutation" \
    "$(fails113 apply_prepared_cluster_config "$prepared" "$expected" "$canonical" "$legacy" "$host_conf" "$hosts_file")" 113
ok "blocked apply preserves canonical" \
    "$(_cluster_config_cli sha256 "$canonical")" "$old_canonical_sha"

echo "cluster-config.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
