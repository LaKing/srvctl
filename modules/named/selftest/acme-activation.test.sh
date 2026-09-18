#!/bin/bash
#
# modules/named/selftest/acme-activation.test.sh — libs/acmelib.sh.
#
#   named_regenerate_activate  prepare -> namedcfg -> restart_named -> commit
#                              under the activation lock: overlapping
#                              regenerates are serialized; the DNS-01
#                              manifest is committed only after a successful
#                              restart and only when its confSha256 is the
#                              live srvctl.conf; a failed generation, restart
#                              or commit fails the regenerate; a crash before
#                              the commit is healed by the next regenerate.
#   named_prepare_acme_zone    primary only: tsig-keygen -a hmac-sha256 key
#                              (0640, root:named) and a seed zone, each only
#                              if missing; replica: slave zone enabled only
#                              while the primary answers for _acme.
#   named_acme_delegation_records  printed for review only.
# namedcfg, restart_named, tsig-keygen, dig and chown are stubbed; the DNS
# role comes from the real topology-cli.js --acme.
#
# Run: bash modules/named/selftest/acme-activation.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export SC_INSTALL_DIR="$REPO" SC_COMPANY_DOMAIN="cdn.test" SRVCTL="srvctl-test"
export SC_CLUSTERS_FILE="$TMP/clusters.json" SC_ACME_KEY_FILE="$TMP/named/srvctl-acme.key"
export SC_ACME_SEED_DIR="$TMP/named/dynamic" SC_NAMED_STATE_DIR="$TMP/state" SC_NAMED_CONF="$TMP/named/srvctl.conf"
export SC_NAMED_ACTIVATE_LOCK="$TMP/activate.lock" LOG="$TMP/log"
mkdir -p "$TMP/named" "$TMP/state" "$TMP/bin"
cat > "$SC_CLUSTERS_FILE" << 'EOF'
{"c1": {"r2.cdn.test": {"host_ip": "192.0.2.2", "dns_server": "master", "dns_primary": true},
        "s1.cdn.test": {"host_ip": "192.0.2.3", "dns_server": "slave"},
        "h3.other.test": {"host_ip": "192.0.2.4"}}}
EOF
cat > "$TMP/bin/tsig-keygen" << 'EOF'
#!/bin/bash
echo "tsig-keygen $*" >> "$LOG"
printf 'key "%s" {\n\talgorithm %s;\n\tsecret "c2VjcmV0";\n};\n' "${@: -1}" "$2"
EOF
cat > "$TMP/bin/dig" << 'EOF'
#!/bin/bash
echo "dig $*" >> "$LOG"
[[ -f "$DIG_ANSWER" ]] && cat "$DIG_ANSWER"
exit 0
EOF
chmod +x "$TMP/bin/tsig-keygen" "$TMP/bin/dig"
export PATH="$TMP/bin:$PATH" DIG_ANSWER="$TMP/dig.answer"

ERRS="$TMP/errs"
# shellcheck disable=SC2329 # called by the sourced lib
msg() { :; }
# shellcheck disable=SC2329
err() { echo "$*" >> "$ERRS"; }
# shellcheck source=/dev/null
source "$REPO/modules/named/libs/acmelib.sh"
# shellcheck disable=SC2329 # replaces chown for an unprivileged run
named_acme_chown() { echo "chown $*" >> "$LOG"; }

# --- prepare on the primary ----------------------------------------------------
HOSTNAME=r2.cdn.test
named_prepare_acme_zone
ok "key via tsig-keygen hmac-sha256" "$(grep -c '^tsig-keygen -a hmac-sha256 srvctl-acme$' "$LOG")" "1"
ok "key mode 640" "$(stat -c '%a' "$SC_ACME_KEY_FILE")" "640"
ok "key owned root:named" "$(grep -c 'chown root:named' "$LOG")" "1"
ok "key is not HMAC-MD5" "$(grep -ci 'md5' "$SC_ACME_KEY_FILE")" "0"
SEED="$SC_ACME_SEED_DIR/_acme.cdn.test.zone"
# shellcheck disable=SC2016 # literal $TTL zone-file directive
ok "seed zone SOA and NS" "$(grep -v '^;' "$SEED")" '$TTL 60
@        IN SOA        ns1.cdn.test. hostmaster.cdn.test. ( 1 15M 5M 1W 60 )
        IN         NS        ns1.cdn.test.
        IN         NS        ns2.cdn.test.'
echo "; owned by BIND now" >> "$SEED"
before="$(sha256sum < "$SEED")"
named_prepare_acme_zone
ok "key created only once" "$(grep -c '^tsig-keygen' "$LOG")" "1"
ok "seed never overwritten" "$(sha256sum < "$SEED")" "$before"

# --- prepare on a replica / without tsig-keygen --------------------------------
rm -f "$SC_ACME_KEY_FILE"; : > "$LOG"
HOSTNAME=s1.cdn.test
echo "ns1.cdn.test. hostmaster.cdn.test. 5 900 300 604800 60" > "$DIG_ANSWER"
named_prepare_acme_zone
ok "replica never creates the key" "$([[ -e "$SC_ACME_KEY_FILE" ]] && echo yes || echo no)" "no"
ok "replica probes the primary's _acme SOA" "$(grep -c '@192.0.2.2 _acme.cdn.test SOA' "$LOG")" "1"
ok "replica enables the slave zone while the primary serves it" "$([[ -e "$SC_NAMED_STATE_DIR/acme-zone.enabled" ]] && echo yes || echo no)" "yes"
rm -f "$DIG_ANSWER"
named_prepare_acme_zone
ok "replica disables the slave zone otherwise" "$([[ -e "$SC_NAMED_STATE_DIR/acme-zone.enabled" ]] && echo yes || echo no)" "no"
HOSTNAME=r2.cdn.test
: > "$ERRS"
PATH="/usr/bin:/bin" named_prepare_acme_zone
ok "no tsig-keygen: reported, zone stays disabled" "$(grep -c 'tsig-keygen is missing' "$ERRS")/$([[ -e "$SC_ACME_KEY_FILE" ]] && echo key || echo nokey)" "1/nokey"

# --- activation: commit only after a successful restart, hash-bound ----------
# namedcfg stub: renders a configuration and a manifest for it
# shellcheck disable=SC2329
namedcfg() {
    local gen="${GEN:-g}"
    echo "namedcfg-start $gen" >> "$LOG"
    sleep "${SLOW:-0}"
    echo "conf $gen" > "$SC_NAMED_CONF"
    printf '{"confSha256":"%s","gen":"%s"}\n' "$(sha256sum < "$SC_NAMED_CONF" | cut -d' ' -f1)" "$gen" \
        > "$SC_NAMED_STATE_DIR/acme-zones.next.json"
    echo "namedcfg-end $gen" >> "$LOG"
}
# shellcheck disable=SC2329
restart_named() {
    echo "restart $(cat "$SC_NAMED_CONF")" >> "$LOG"
    sleep "${SLOW:-0}"
    [[ -n "${CRASH:-}" ]] && exit 137
    return "${RESTART_RC:-0}"
}
committed() { node -e 'try{process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).gen)}catch(e){process.stdout.write("none")}' "$SC_NAMED_STATE_DIR/acme-zones.json"; }
live_matches() { [[ "$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).confSha256)' "$SC_NAMED_STATE_DIR/acme-zones.json")" == "$(sha256sum < "$SC_NAMED_CONF" | cut -d' ' -f1)" ]] && echo yes || echo no; }

: > "$LOG"
GEN=a RESTART_RC=1 named_regenerate_activate; rc=$?
ok "failed restart: regenerate fails" "$rc" "1"
ok "failed restart: nothing committed" "$(committed)" "none"

# failed generation: reported, BIND is not restarted, nothing committed
# shellcheck disable=SC2329 # called by named_regenerate_activate
namedcfg() { echo "namedcfg-fail" >> "$LOG"; return 1; }
: > "$LOG"; : > "$ERRS"
named_regenerate_activate; rc=$?
ok "failed namedcfg: regenerate fails" "$rc" "1"
ok "failed namedcfg: reported" "$(grep -c 'generation failed' "$ERRS")" "1"
ok "failed namedcfg: no restart, nothing committed" "$(grep -c '^restart' "$LOG")/$(committed)" "0/none"
unset -f namedcfg
# shellcheck disable=SC2329
namedcfg() {
    local gen="${GEN:-g}"
    echo "namedcfg-start $gen" >> "$LOG"
    sleep "${SLOW:-0}"
    echo "conf $gen" > "$SC_NAMED_CONF"
    printf '{"confSha256":"%s","gen":"%s"}\n' "$(sha256sum < "$SC_NAMED_CONF" | cut -d' ' -f1)" "$gen" \
        > "$SC_NAMED_STATE_DIR/acme-zones.next.json"
    echo "namedcfg-end $gen" >> "$LOG"
}
GEN=b named_regenerate_activate; rc=$?
ok "successful activation" "$rc" "0"
ok "manifest committed for the active configuration" "$(committed)/$(live_matches)" "b/yes"

# the live configuration changed after rendering: no commit
# shellcheck disable=SC2329 # called by named_regenerate_activate
namedcfg() { GEN=c; echo "conf c" > "$SC_NAMED_CONF"; printf '{"confSha256":"%s","gen":"c"}\n' "stale" > "$SC_NAMED_STATE_DIR/acme-zones.next.json"; }
: > "$ERRS"
named_regenerate_activate; rc=$?
ok "hash mismatch: regenerate fails" "$rc" "1"
ok "hash mismatch: previous manifest kept" "$(committed)" "b"
ok "hash mismatch: reported" "$(grep -c 'does not match the active BIND configuration' "$ERRS")" "1"
unset -f namedcfg
# shellcheck disable=SC2329
namedcfg() {
    local gen="${GEN:-g}"
    echo "namedcfg-start $gen" >> "$LOG"
    sleep "${SLOW:-0}"
    echo "conf $gen" > "$SC_NAMED_CONF"
    printf '{"confSha256":"%s","gen":"%s"}\n' "$(sha256sum < "$SC_NAMED_CONF" | cut -d' ' -f1)" "$gen" \
        > "$SC_NAMED_STATE_DIR/acme-zones.next.json"
    echo "namedcfg-end $gen" >> "$LOG"
}

# crash between restart and commit, healed by the next regenerate
( GEN=d CRASH=1 named_regenerate_activate ); rc=$?
ok "crash before commit" "$rc/$(committed)" "137/b"
GEN=e named_regenerate_activate
ok "next regenerate commits" "$(committed)/$(live_matches)" "e/yes"

# overlapping regenerates are serialized and each commit matches its config
: > "$LOG"
( GEN=x SLOW=0.4 named_regenerate_activate ) &
sleep 0.1
( GEN=y SLOW=0.4 named_regenerate_activate ) &
wait
ok "overlapping regenerates serialized" "$(grep -v '^dig\|^tsig\|^chown' "$LOG" | tr '\n' '|')" \
  "namedcfg-start x|namedcfg-end x|restart conf x|namedcfg-start y|namedcfg-end y|restart conf y|"
ok "final manifest matches the active configuration" "$(committed)/$(live_matches)" "y/yes"

# --- delegation records for review ----------------------------------------------
ok "delegation records" "$(named_acme_delegation_records)" "; DNS-01 delegation for review — NOT applied by srvctl.
; Add to the cdn.test zone (hand-maintained, included via /var/named/d250.conf) and raise its serial.
_acme                          IN NS    ns1.cdn.test.
_acme                          IN NS    ns2.cdn.test.
; optional, per configured host name that should get its certificate via DNS-01:
_acme-challenge.r2             IN CNAME r2.cdn.test._acme.cdn.test.
_acme-challenge.s1             IN CNAME s1.cdn.test._acme.cdn.test."

if command -v shellcheck > /dev/null; then
  ok "acmelib shellcheck" "$(shellcheck "$REPO/modules/named/libs/acmelib.sh" > /dev/null 2>&1 && echo clean || echo dirty)" "clean"
fi

echo ""
echo "acme-activation.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
