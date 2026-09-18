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

echo ""
echo "runlock.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
