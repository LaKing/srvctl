#!/bin/bash
#
# modules/certificates/selftest/certselect.test.sh — cert selection + prune.
#
# Generates real certs with openssl and drives sync_haproxy_certificates over
# temp source/target dirs (SC_ADMIN_CERT_DIR, SC_DATASTORE_DIR/cert, target arg)
# to prove: wildcard preferred over per-domain for covered domains; per-domain
# certs served for uncovered domains; expired certs never served; stale copies
# and now-wildcard-covered per-domain copies pruned; newer wins; files are 0600.
#
# Run: bash modules/certificates/selftest/certselect.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
export SRVCTL=1

# certselectlib uses check_wildcard_pem from wildcardcertlib.
# shellcheck source=/dev/null
source "$REPO/modules/certificates/libs/wildcardcertlib.sh"
# msg used by wildcardcertlib (invoked indirectly when the lib is sourced)
# shellcheck disable=SC2329
msg() { :; }
# shellcheck source=/dev/null
source "$REPO/modules/certificates/libs/certselectlib.sh"

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# gen_cert CN DAYS OUTFILE  — self-contained cert+key pem (leaf-first), DAYS may
# be negative for an already-expired cert (openssl -days needs >0, so backdate).
gen_cert() {
  local cn="$1" days="$2" out="$3" key crt
  key="$(mktemp)"; crt="$(mktemp)"
  if [[ "$days" -lt 0 ]]; then
    # already-expired: valid window entirely in the past
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$key" -out "$crt" \
      -subj "/CN=$cn" -days 1 -not_before 20200101000000Z -not_after 20200102000000Z > /dev/null 2>&1 \
    || openssl req -x509 -newkey rsa:2048 -nodes -keyout "$key" -out "$crt" -subj "/CN=$cn" -days 1 > /dev/null 2>&1
  else
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$key" -out "$crt" -subj "/CN=$cn" -days "$days" > /dev/null 2>&1
  fi
  cat "$crt" "$key" > "$out"
  rm -f "$key" "$crt"
}

ADMIN="$TMP/etc-cert"; DS="$TMP/datastore"; HA="$TMP/haproxy"
mkdir -p "$ADMIN/example.test" "$DS/cert" "$HA"
export SC_ADMIN_CERT_DIR="$ADMIN" SC_DATASTORE_DIR="$DS"

# --- sources ----------------------------------------------------------------
gen_cert '*.example.test' 800 "$ADMIN/example.test/example.test.pem"   # valid wildcard
gen_cert 'blog.example.test' 60 "$DS/cert/blog.example.test.pem"       # LE, COVERED by wildcard
gen_cert 'shop.example.test' 60 "$DS/cert/shop.example.test.pem"       # LE, COVERED by wildcard
gen_cert 'printhub.other'    60 "$DS/cert/printhub.other.pem"          # LE, NOT covered
gen_cert 'deep.a.example.test' 60 "$DS/cert/deep.a.example.test.pem"   # two labels: NOT covered by *.example.test
gen_cert 'gone.other'        -1 "$DS/cert/gone.other.pem"              # EXPIRED, uncovered

# pre-existing stale files in the haproxy dir (must be pruned)
gen_cert '*.example.test'    10 "$HA/example.test.pem"                 # OLD wildcard copy (will be replaced by newer)
gen_cert 'blog.example.test' 10 "$HA/blog.example.test.pem"           # stale per-domain shadow (must be pruned)
: > "$HA/ca-bundle.pem"                                                # must be pruned

# unit checks
ok "domain_under_wildcard blog"      "$(domain_under_wildcard blog.example.test example.test && echo y || echo n)" "y"
ok "domain_under_wildcard bare"      "$(domain_under_wildcard example.test example.test && echo y || echo n)" "y"
ok "domain_under_wildcard two-label" "$(domain_under_wildcard deep.a.example.test example.test && echo y || echo n)" "n"
ok "cert_valid on fresh"             "$(cert_valid "$DS/cert/blog.example.test.pem" && echo y || echo n)" "y"
ok "cert_valid on expired"           "$(cert_valid "$DS/cert/gone.other.pem" && echo y || echo n)" "n"

# --- run the sync -----------------------------------------------------------
sync_haproxy_certificates "$HA"

present() { [[ -f "$HA/$1" ]] && echo yes || echo no; }
ok "wildcard deployed"                 "$(present example.test.pem)" "yes"
ok "covered blog: NO per-domain (wildcard wins)" "$(present blog.example.test.pem)" "no"
ok "covered shop: NO per-domain (wildcard wins)" "$(present shop.example.test.pem)" "no"
ok "uncovered printhub: per-domain served"       "$(present printhub.other.pem)" "yes"
ok "two-label deep: per-domain served (not covered)" "$(present deep.a.example.test.pem)" "yes"
ok "expired gone.other: NOT served"    "$(present gone.other.pem)" "no"
ok "ca-bundle pruned"                  "$(present ca-bundle.pem)" "no"

# newer wildcard replaced the old stale copy in place
ok "wildcard copy is the NEW one (>=1yr)" "$(cert_valid "$HA/example.test.pem" && [[ "$(cert_notafter_epoch "$HA/example.test.pem")" -gt "$(date -d '+300 days' +%s)" ]] && echo y || echo n)" "y"
# deployed files are 0600
ok "deployed files are mode 600" "$(stat -c '%a' "$HA/example.test.pem")" "600"

# nothing unexpected left behind (bash globs are sorted; skip if none matched)
left=""
for f in "$HA"/*.pem; do [[ -e "$f" ]] && left+="$(basename "$f") "; done
ok "final haproxy dir = wildcard + uncovered per-domain only" "$left" "deep.a.example.test.pem example.test.pem printhub.other.pem "

echo ""
echo "certselect.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
