#!/bin/bash
#
# modules/letsencrypt/selftest/acme-dns-hook.test.sh — certbot DNS-01 hooks.
#
# dig and nsupdate are stubbed through PATH; /proc is a fake tree
# (SC_ACME_PROC) so the owner walk and "provably ended" can be exercised.
# Every hook run is standalone, as certbot starts it (P6):
#   env -i PATH=... CERTBOT_DOMAIN=... CERTBOT_VALIDATION=... SC_ACME_HOOK_CONF=...
# Proves: auth checks the primary's CNAME before publishing, sends the exact
# nsupdate script, and returns only when the primary and every secondary serve
# the CNAME to the target and the TXT value (non-zero on timeout); cleanup
# deletes only its value and marks a failed delete; reconcile retries or
# removes a record only when its certbot owner provably ended (process gone,
# different start time, different boot id), never for a live or unknown owner.
#
# Run: bash modules/letsencrypt/selftest/acme-dns-hook.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
HOOK="$REPO/modules/letsencrypt/apps/acme-dns-hook.sh"

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUB="$TMP/stub"; BIN="$TMP/bin"; PROC="$TMP/proc"
mkdir -p "$STUB/dig" "$BIN" "$PROC/sys/kernel/random"
echo boot-1 > "$PROC/sys/kernel/random/boot_id"

# dig @server ... NAME TYPE -> $STUB/dig/<server>/<name>/<type>, optionally
# only from the Nth query on (<type>.after holds N)
cat > "$BIN/dig" << 'EOF'
#!/bin/bash
server=""; for a in "$@"; do [[ "$a" == @* ]] && server="${a#@}"; done
name="${@: -2:1}"; type="${@: -1}"
f="$STUB/dig/$server/$name/$type"
n=0; [[ -f "$f.count" ]] && n="$(cat "$f.count")"; n=$((n + 1)); echo "$n" > "$f.count" 2> /dev/null
if [[ -f "$f.after" ]] && (( n < $(cat "$f.after") )); then exit 0; fi
[[ -f "$f" ]] && cat "$f"
exit 0
EOF
cat > "$BIN/nsupdate" << 'EOF'
#!/bin/bash
{ echo "ARGS $*"; cat; echo "--"; } >> "$STUB/nsupdate.log"
[[ -f "$STUB/nsupdate.fail" ]] && exit 2
exit 0
EOF
chmod +x "$BIN/dig" "$BIN/nsupdate"

CONF="$TMP/hook.conf"
cat > "$CONF" << EOF
ACME_ZONE=_acme.cdn.test
ACME_KEY=$TMP/acme.key
ACME_PRIMARY=10.0.0.1
ACME_SECONDARIES=10.0.0.2 10.0.0.3
ACME_TTL=60
ACME_TIMEOUT=2
ACME_POLL=0
ACME_STATE_DIR=$TMP/state
ACME_LOCK=$TMP/records.lock
EOF

answer() { mkdir -p "$STUB/dig/$1/$2"; printf '%s\n' "$4" > "$STUB/dig/$1/$2/$3"; rm -f "$STUB/dig/$1/$2/$3.count"; }
fakeproc() { # pid "cmd args" ppid starttime
  local pid="$1" rest i
  mkdir -p "$PROC/$pid"
  # shellcheck disable=SC2086 # split the command line into argv entries
  printf '%s\0' $2 > "$PROC/$pid/cmdline"
  rest="S $3"; for ((i = 5; i <= 21; i++)); do rest+=" 0"; done; rest+=" $4 0 0 0"
  echo "$pid (${2%% *}) $rest" > "$PROC/$pid/stat"
}
fakeproc 4242 "/usr/bin/python3 /usr/bin/certbot certonly --manual" 1 777

VALUE="abcdefghijklmnopqrstuvwxyz0123456789-_ABCDE"
# run_hook MODE DOMAIN [certbot|none] — standalone, from a subshell whose
# fake /proc entry is "sh -c hook" under certbot (4242) or under init
run_hook() {
  local mode="$1" domain="$2" parent="${3:-certbot}"
  (
    me="$BASHPID"
    if [[ "$parent" == certbot ]]; then fakeproc "$me" "sh -c hook" 4242 900; else fakeproc "$me" "bash" 1 900; fi
    env -i PATH="$BIN:/usr/bin:/bin" CERTBOT_DOMAIN="$domain" CERTBOT_VALIDATION="$VALUE" \
      SC_ACME_HOOK_CONF="$CONF" SC_ACME_PROC="$PROC" STUB="$STUB" bash "$HOOK" "$mode"
    rc=$?   # keeps bash from exec-ing the hook in place of this subshell
    exit "$rc"
  )
}
records() { local n=0 f; for f in "$TMP/state/inflight"/*.rec; do [[ -f "$f" ]] && n=$((n + 1)); done; echo "$n"; }
field() { grep "^$2=" "$1" | cut -d= -f2-; }

T="a.test._acme.cdn.test"
for s in 10.0.0.1 10.0.0.2 10.0.0.3; do answer "$s" "_acme-challenge.a.test" CNAME "$T."; done
answer 10.0.0.1 "$T" TXT "\"$VALUE\""
answer 10.0.0.2 "$T" TXT "\"$VALUE\""
answer 10.0.0.3 "$T" TXT "\"$VALUE\""
echo 3 > "$STUB/dig/10.0.0.3/$T/TXT.after"   # the second secondary serves the TXT from its 3rd query

# --- auth: waits for the full chain on every secondary ---------------------
run_hook auth a.test > "$TMP/out" 2>&1; rc=$?
ok "auth returns 0 once every server serves CNAME and TXT" "$rc" "0"
ok "auth waited for the slow secondary" "$(( $(cat "$STUB/dig/10.0.0.3/$T/TXT.count") >= 3 ))" "1"
ok "exact nsupdate script" "$(sed -n '1,5p' "$STUB/nsupdate.log")" \
"ARGS -k $TMP/acme.key
server 10.0.0.1
zone _acme.cdn.test
update add $T 60 IN TXT \"$VALUE\"
send"
rec="$(ls "$TMP"/state/inflight/*.rec)"
ok "in-flight record owner is the certbot ancestor" "$(field "$rec" pid)/$(field "$rec" starttime)/$(field "$rec" bootid)/$(field "$rec" status)" "4242/777/boot-1/inflight"

# --- auth: a secondary without the CNAME, or with another target -> timeout
rm -f "$STUB/nsupdate.log"
answer 10.0.0.2 "_acme-challenge.b.test" CNAME ""
answer 10.0.0.1 "_acme-challenge.b.test" CNAME "b.test._acme.cdn.test."
answer 10.0.0.3 "_acme-challenge.b.test" CNAME "b.test._acme.cdn.test."
for s in 10.0.0.1 10.0.0.2 10.0.0.3; do answer "$s" "b.test._acme.cdn.test" TXT "\"$VALUE\""; done
run_hook auth b.test > "$TMP/out" 2>&1; rc=$?
ok "missing CNAME on a secondary: timeout, non-zero" "$rc" "1"
ok "timeout is reported" "$(grep -c 'not visible on 10.0.0.2' "$TMP/out")" "1"
answer 10.0.0.2 "_acme-challenge.b.test" CNAME "other._acme.cdn.test."
run_hook auth b.test > /dev/null 2>&1; rc=$?
ok "different CNAME target on a secondary: non-zero" "$rc" "1"

# --- auth: primary CNAME not into the challenge zone -> nothing published --
rm -f "$STUB/nsupdate.log"
answer 10.0.0.1 "_acme-challenge.c.test" CNAME "c.test.elsewhere.example."
run_hook auth c.test > "$TMP/out" 2>&1; rc=$?
ok "wrong CNAME on the primary: refused" "$rc" "1"
ok "no nsupdate for a wrong CNAME" "$([[ -f "$STUB/nsupdate.log" ]] && echo called || echo none)" "none"
run_hook auth "bad domain" > /dev/null 2>&1; rc=$?
ok "invalid CERTBOT_DOMAIN refused" "$rc" "1"

# --- cleanup ----------------------------------------------------------------
rm -f "$TMP"/state/inflight/*.rec "$STUB/nsupdate.log"
run_hook auth a.test > /dev/null 2>&1
run_hook cleanup a.test > /dev/null 2>&1; rc=$?
ok "cleanup exit 0" "$rc" "0"
ok "cleanup deletes exactly its value" "$(grep '^update' "$STUB/nsupdate.log" | tail -1)" "update delete $T IN TXT \"$VALUE\""
ok "cleanup removes the record" "$(records)" "0"

run_hook auth a.test > /dev/null 2>&1
touch "$STUB/nsupdate.fail"
run_hook cleanup a.test > "$TMP/out" 2>&1; rc=$?
ok "failed cleanup still exits 0" "$rc" "0"
ok "failed cleanup is observable" "$(grep -c 'left for reconcile' "$TMP/out")" "1"
rec="$(ls "$TMP"/state/inflight/*.rec)"
ok "failed cleanup marked" "$(field "$rec" status)" "cleanupFailed"

# --- reconcile: only when the owner provably ended ---------------------------
reconcile() { env -i PATH="$BIN:/usr/bin:/bin" SC_ACME_HOOK_CONF="$CONF" SC_ACME_PROC="$PROC" STUB="$STUB" bash "$HOOK" reconcile 2> "$TMP/rec.err"; }
rm -f "$STUB/nsupdate.fail" "$STUB/nsupdate.log"
ok "live owner: kept" "$(reconcile)" "reconcile deleted=0 failed=0 live=1 unknown=0"
ok "live owner: no delete sent" "$([[ -f "$STUB/nsupdate.log" ]] && echo called || echo none)" "none"
fakeproc 4242 "/usr/bin/python3 /usr/bin/certbot certonly --manual" 1 999   # pid reused
ok "reused pid (other start time): retried" "$(reconcile)" "reconcile deleted=1 failed=0 live=0 unknown=0"
ok "record removed after a successful retry" "$(records)" "0"

fakeproc 4242 "/usr/bin/python3 /usr/bin/certbot certonly --manual" 1 777
run_hook auth a.test > /dev/null 2>&1
echo boot-2 > "$PROC/sys/kernel/random/boot_id"
touch "$STUB/nsupdate.fail"
ok "new boot, delete fails: counted, kept" "$(reconcile)" "reconcile deleted=0 failed=1 live=0 unknown=0"
ok "record kept when the retry fails" "$(records)" "1"
rm -f "$STUB/nsupdate.fail"
ok "new boot: retried" "$(reconcile)" "reconcile deleted=1 failed=0 live=0 unknown=0"
echo boot-1 > "$PROC/sys/kernel/random/boot_id"

run_hook auth a.test > /dev/null 2>&1
rm -rf "${PROC:?}/4242"
ok "owner gone: retried" "$(reconcile)" "reconcile deleted=1 failed=0 live=0 unknown=0"

run_hook auth a.test none > /dev/null 2>&1
rec="$(ls "$TMP"/state/inflight/*.rec)"
ok "no certbot ancestor: owner unknown" "$(field "$rec" pid)" "unknown"
ok "unknown owner: never removed" "$(reconcile)" "reconcile deleted=0 failed=0 live=0 unknown=1"
ok "unknown owner: reported" "$(grep -c 'no known certbot owner' "$TMP/rec.err")" "1"
rm -f "$TMP"/state/inflight/*.rec

# --- concurrency: reconcile waits for a holder of the records lock -----------
( flock "$TMP/records.lock" bash -c "sleep 1; echo held-done > '$TMP/order'" ) &
sleep 0.2
reconcile > /dev/null
echo reconcile-done >> "$TMP/order"
wait
ok "reconcile serialized behind the records lock" "$(tr '\n' ' ' < "$TMP/order")" "held-done reconcile-done "

if command -v shellcheck > /dev/null; then
  ok "hook shellcheck" "$(shellcheck "$HOOK" > /dev/null 2>&1 && echo clean || echo dirty)" "clean"
fi

echo ""
echo "acme-dns-hook.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
