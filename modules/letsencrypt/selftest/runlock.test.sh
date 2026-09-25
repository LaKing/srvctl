#!/bin/bash
#
# modules/letsencrypt/selftest/runlock.test.sh — letsencrypt shell glue.
#
#   letsencrypt_main (libs/bashlib.sh) runs letsencrypt.js under the run lock:
#   two concurrent runs never overlap (they own the handover state, journal
#   and certbot lineages).
#   acme_snapshot_manifest (libs/letsencryptlib.sh) copies the committed
#   DNS-01 manifest and the live srvctl.conf hash under a SHARED hold of the
#   named activation lock: consistent pair, nothing when no manifest exists,
#   nothing (and an error) while an activation holds the lock.
#
# Run: bash modules/letsencrypt/selftest/runlock.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ERRS="$TMP/errs"
# shellcheck disable=SC2329 # called by the sourced libs
err() { echo "$*" >> "$ERRS"; }
# shellcheck disable=SC2329
msg() { :; }
# shellcheck disable=SC2329
run() { :; }
# shellcheck source=/dev/null
source "$REPO/modules/letsencrypt/libs/bashlib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/letsencrypt/libs/letsencryptlib.sh"

# --- run lock -----------------------------------------------------------------
mkdir -p "$TMP/install/modules/letsencrypt"
cat > "$TMP/install/modules/letsencrypt/letsencrypt.js" << 'EOF'
const fs = require("fs");
const log = process.env.RUN_LOG;
fs.appendFileSync(log, "start " + process.argv[2] + "\n");
const until = Date.now() + 700;
while (Date.now() < until) { /* busy */ }
fs.appendFileSync(log, "end " + process.argv[2] + "\n");
EOF
export SC_INSTALL_DIR="$TMP/install" SC_LETSENCRYPT_LOCK="$TMP/le.lock" RUN_LOG="$TMP/run.log"
letsencrypt_main one &
sleep 0.1
letsencrypt_main two &
wait
ok "concurrent runs are serialized" "$(tr '\n' ' ' < "$TMP/run.log")" "start one end one start two end two "

# --- manifest snapshot under the shared activation lock ----------------------
export SC_ACME_DIR="$TMP/acme" SC_NAMED_STATE_DIR="$TMP/named" SC_NAMED_CONF="$TMP/srvctl.conf" \
  SC_NAMED_ACTIVATE_LOCK="$TMP/activate.lock" SC_ACME_SNAPSHOT_WAIT=1
mkdir -p "$SC_NAMED_STATE_DIR"
echo 'zone "a.test" {};' > "$SC_NAMED_CONF"
acme_snapshot_manifest
ok "no committed manifest: no snapshot" "$([[ -e "$SC_ACME_DIR/manifest.snapshot.json" ]] && echo yes || echo no)" "no"

echo '{"confSha256":"x"}' > "$SC_NAMED_STATE_DIR/acme-zones.json"
acme_snapshot_manifest
ok "snapshot copied" "$(cat "$SC_ACME_DIR/manifest.snapshot.json")" '{"confSha256":"x"}'
ok "live hash taken with it" "$(cut -d' ' -f1 "$SC_ACME_DIR/manifest.live.sha256")" "$(sha256sum < "$SC_NAMED_CONF" | cut -d' ' -f1)"

( flock "$SC_NAMED_ACTIVATE_LOCK" sleep 2 ) &
sleep 0.3
: > "$ERRS"
acme_snapshot_manifest
wait
ok "activation in progress: no (stale) snapshot" "$([[ -e "$SC_ACME_DIR/manifest.snapshot.json" ]] && echo yes || echo no)" "no"
ok "activation in progress: reported" "$(grep -c 'could not snapshot' "$ERRS")" "1"

( flock -s "$SC_NAMED_ACTIVATE_LOCK" sleep 2 ) &
sleep 0.3
acme_snapshot_manifest
wait
ok "another shared holder does not block the snapshot" "$([[ -e "$SC_ACME_DIR/manifest.snapshot.json" ]] && echo yes || echo no)" "yes"

# --- acme-server setup is repaired by regenerate ----------------------------------
# ensure_acme_server rewrites a missing or stale unit (restarting the server
# only then) and leaves an up-to-date one alone.
CALLS="$TMP/calls"
# shellcheck disable=SC2329 # stand-ins for an unprivileged run
systemctl() { echo "systemctl $*" >> "$CALLS"; }
# shellcheck disable=SC2329
getent() { return 0; }
# shellcheck disable=SC2329
chown() { :; }
UNIT="$TMP/acme-server.service"
: > "$CALLS"
ensure_acme_server "$UNIT" "$TMP/webroot"
ok "missing unit is written" "$(grep -c "ExecStart=/bin/node $SC_INSTALL_DIR/modules/letsencrypt/apps/acme-server.js" "$UNIT")" "1"
ok "new unit: daemon-reload and try-restart" "$(tr '\n' '|' < "$CALLS")" "systemctl daemon-reload|systemctl try-restart acme-server.service|"
ok "webroot created" "$([[ -d $TMP/webroot ]] && echo yes || echo no)" "yes"
: > "$CALLS"
ensure_acme_server "$UNIT" "$TMP/webroot"
ok "unchanged unit: no systemctl call" "$(cat "$CALLS")" ""
sed -i 's|ExecStart=.*|ExecStart=/bin/node /usr/local/share/srvctl/modules/certificates/acme-server.js|' "$UNIT"
ensure_acme_server "$UNIT" "$TMP/webroot"
ok "stale ExecStart is repaired" "$(grep -c "apps/acme-server.js" "$UNIT")" "1"
ok "stale unit: server restarted" "$(tr '\n' '|' < "$CALLS")" "systemctl daemon-reload|systemctl try-restart acme-server.service|"
ok "no temp file left" "$(find "$TMP" -maxdepth 1 -name 'acme-server.service.*' | wc -l)" "0"
unset -f systemctl getent chown

# --- operator knobs reach letsencrypt.js -----------------------------------------
# /etc/srvctl/*.conf is sourced, not exported; regenerate_letsencrypt hands the
# DNS-01 knobs to the node process only when they are set.
# shellcheck disable=SC2329 # replaces systemctl/mkdir/letsencrypt_main for an unprivileged run
systemctl() { echo active; }
# shellcheck disable=SC2329
mkdir() { :; }
# shellcheck disable=SC2329
acme_snapshot_manifest() { :; }
# shellcheck disable=SC2329
ensure_acme_server() { :; }
# shellcheck disable=SC2329
letsencrypt_main() { env | grep -E '^SC_(ACME_(MAX_ISSUE_PER_RUN|HTTP01_MAX_PER_RUN|DNS01_ONLY|HTTP01_FALLBACK)|LETSENCRYPT_STAGING|WILDCARD_EXCLUDE)=' | sort | tr '\n' '|'; }
# shellcheck disable=SC2034 # read by the sourced lib
SC_DATASTORE_DIR="$TMP/ds" CMD=regenerate
ok "unset knobs: only the fallback default is exported" "$(regenerate_letsencrypt 2> /dev/null | tail -1)" "SC_ACME_HTTP01_FALLBACK=false|"
# shellcheck disable=SC2034 # read by the sourced lib
SC_ACME_MAX_ISSUE_PER_RUN=0 SC_ACME_DNS01_ONLY="a.test b.test" SC_LETSENCRYPT_STAGING=true SC_ACME_HTTP01_MAX_PER_RUN=3
ok "set knobs are exported (0 included)" "$(regenerate_letsencrypt 2> /dev/null | tail -1)" \
  "SC_ACME_DNS01_ONLY=a.test b.test|SC_ACME_HTTP01_FALLBACK=false|SC_ACME_HTTP01_MAX_PER_RUN=3|SC_ACME_MAX_ISSUE_PER_RUN=0|SC_LETSENCRYPT_STAGING=true|"
unset SC_ACME_MAX_ISSUE_PER_RUN SC_ACME_DNS01_ONLY SC_LETSENCRYPT_STAGING SC_ACME_HTTP01_MAX_PER_RUN

# --- a failed letsencrypt run never aborts the certificate hook -----------------
# (the haproxy sync after it must still serve the existing certificates)
# shellcheck disable=SC2329
letsencrypt_main() { return 1; }
: > "$ERRS"
regenerate_letsencrypt > /dev/null 2>&1
ok "failed run: regenerate_letsencrypt returns 0" "$?" "0"
ok "failed run: error logged" "$(grep -c 'letsencrypt run failed (exit 1)' "$ERRS")" "1"
# shellcheck disable=SC2329
letsencrypt_main() { return 0; }
: > "$ERRS"
regenerate_letsencrypt > /dev/null 2>&1
ok "clean run: no error" "$(grep -c 'letsencrypt run failed' "$ERRS")" "0"

echo ""
echo "runlock.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
