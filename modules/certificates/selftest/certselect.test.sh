#!/bin/bash
#
# modules/certificates/selftest/certselect.test.sh — cert selection + prune.
#
# Generates real certs with openssl and drives sync_haproxy_certificates over
# temp source/target dirs (SC_ADMIN_CERT_DIR, SC_DATASTORE_DIR/cert, target arg)
# to prove: wildcard preferred over per-domain for covered domains; per-domain
# certs served for uncovered domains; expired certs never served; stale copies
# and now-wildcard-covered per-domain copies pruned; newer wins; files are 0600.
# Managed DNS-01 wildcards ($SC_DATASTORE_DIR/cert/wildcard/<base>.pem) are
# served as wildcard.<base>.pem only while servable, never overwrite or delete
# a per-domain datastore cert, and lose to a later-expiring admin wildcard.
#
# Run: bash modules/certificates/selftest/certselect.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
export SRVCTL=1

# Source the libs in the relative order load_libs (commonlib.sh) uses: the
# glob order of modules/certificates/libs, i.e. certselectlib.sh first,
# wildcardcertlib.sh, then wildcardgatelib.sh last. certselectlib calls
# check_wildcard_pem / domain_under_wildcard / wildcard_servable_managed from
# wildcardgatelib only at call time, so this order must work.
# shellcheck disable=SC2329
msg() { :; }
# shellcheck source=/dev/null
source "$REPO/modules/certificates/libs/certselectlib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/certificates/libs/wildcardcertlib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/certificates/libs/wildcardgatelib.sh"

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

# --- service_key_pem: one COMBINED pem must serve the mail/gui services too ---
# (install_service_hostcertificate references run/err/create_selfsigned but
#  service_key_pem does not; sourcing only defines functions.)
# shellcheck disable=SC2329
err() { :; }
# shellcheck disable=SC2329
run() { :; }
# shellcheck disable=SC1090,SC1091
source "$REPO/modules/certificates/libs/servicecertlib.sh"
SVC="$TMP/svc"; mkdir -p "$SVC"
cp "$DS/cert/printhub.other.pem" "$SVC/combined.pem"                 # cert+chain+key
openssl x509 -in "$SVC/combined.pem" > "$SVC/split.pem" 2> /dev/null # cert only
openssl pkey -in "$SVC/combined.pem" > "$SVC/split.key" 2> /dev/null # key only
ok "combined pem yields a key"     "$(service_key_pem "$SVC" combined > /dev/null && echo y || echo n)" "y"
ok "combined key is a PRIVATE KEY" "$(service_key_pem "$SVC" combined | grep -c 'BEGIN.*PRIVATE KEY')" "1"
ok "separate .key is used"         "$(service_key_pem "$SVC" split > /dev/null && echo y || echo n)" "y"
rm -f "$SVC/split.key"
ok "cert-only pem, no key -> fail" "$(service_key_pem "$SVC" split > /dev/null && echo y || echo n)" "n"

# --- managed DNS-01 wildcards (cert/wildcard/<base>.pem) --------------------
# gen_bundle BASE DAYS OUT [KEYFROM] — key-first bundle like letsencrypt.js
# writes (privkey + fullchain), SAN BASE and *.BASE, CN BASE (no '*' in CN).
gen_bundle() {
  local base="$1" days="$2" out="$3" keyfrom="${4:-}" key crt
  key="$(mktemp)"; crt="$(mktemp)"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$key" -out "$crt" -subj "/CN=$base" \
    -addext "subjectAltName=DNS:$base,DNS:*.$base" -days "$days" > /dev/null 2>&1
  if [[ -n "$keyfrom" ]]; then openssl genpkey -algorithm RSA -out "$key" > /dev/null 2>&1; fi
  cat "$key" "$crt" > "$out"
  rm -f "$key" "$crt"
}

ADMIN2="$TMP/etc-cert2"; DS2="$TMP/datastore2"; HA2="$TMP/haproxy2"
mkdir -p "$ADMIN2/example2.test" "$ADMIN2/both.test" "$DS2/cert/wildcard" "$DS2/cert/wildcard-retired" "$HA2"
export SC_ADMIN_CERT_DIR="$ADMIN2" SC_DATASTORE_DIR="$DS2"

gen_bundle le.test 60 "$DS2/cert/wildcard/le.test.pem"                    # servable managed
gen_cert 'le.test'        60 "$DS2/cert/le.test.pem"                       # per-domain of the same zone
gen_cert 'blog.le.test'   60 "$DS2/cert/blog.le.test.pem"                  # covered per-domain
gen_bundle short.test 1 "$DS2/cert/wildcard/short.test.pem"                # < 1 day left: not servable
gen_cert 'short.test'     60 "$DS2/cert/short.test.pem"                    # must be served instead
gen_bundle badkey.test 60 "$DS2/cert/wildcard/badkey.test.pem" other        # key does not match
gen_cert 'badkey.test'    60 "$DS2/cert/badkey.test.pem"
gen_bundle other.test 60 "$DS2/cert/wildcard/renamed.test.pem"             # file name != SAN base
gen_bundle ret.test 60 "$DS2/cert/wildcard-retired/ret.test.pem"           # retired: never read
gen_cert '*.example2.test' 800 "$ADMIN2/example2.test/example2.test.pem"  # admin, expires later
gen_bundle example2.test 60 "$DS2/cert/wildcard/example2.test.pem"         # managed, expires earlier
gen_cert '*.both.test'     30 "$ADMIN2/both.test/both.test.pem"            # admin, expires earlier
gen_bundle both.test 90 "$DS2/cert/wildcard/both.test.pem"                 # managed, expires later
gen_bundle ret.test 60 "$HA2/wildcard.ret.test.pem"                        # stale served copy
le_before="$(sha256sum < "$DS2/cert/le.test.pem")"

ok "servable managed wildcard"       "$(wildcard_servable_managed "$DS2/cert/wildcard/le.test.pem")" "le.test"
ok "managed with < 1 day left"       "$(wildcard_servable_managed "$DS2/cert/wildcard/short.test.pem")" "false"
ok "managed with a foreign key"      "$(wildcard_servable_managed "$DS2/cert/wildcard/badkey.test.pem")" "false"
ok "managed with a mismatched name"  "$(wildcard_servable_managed "$DS2/cert/wildcard/renamed.test.pem")" "false"

sync_haproxy_certificates "$HA2"
present2() { [[ -f "$HA2/$1" ]] && echo yes || echo no; }
ok "managed served as wildcard.<base>.pem"       "$(present2 wildcard.le.test.pem)" "yes"
ok "managed zone: per-domain not served"         "$(present2 le.test.pem)" "no"
ok "managed zone: covered subdomain not served"  "$(present2 blog.le.test.pem)" "no"
ok "per-domain datastore file left untouched"    "$(sha256sum < "$DS2/cert/le.test.pem")" "$le_before"
ok "not servable managed: not served"            "$(present2 wildcard.short.test.pem)" "no"
ok "not servable managed: per-domain served"     "$(present2 short.test.pem)" "yes"
ok "foreign-key managed: per-domain served"      "$(present2 badkey.test.pem)" "yes"
ok "retired wildcard not served, stale pruned"   "$(present2 wildcard.ret.test.pem)" "no"
ok "admin expiring later wins over managed"      "$(present2 example2.test.pem)/$(present2 wildcard.example2.test.pem)" "yes/no"
ok "managed expiring later wins over admin"      "$(present2 both.test.pem)/$(present2 wildcard.both.test.pem)" "no/yes"
ok "managed wildcard deployed 0600"              "$(stat -c '%a' "$HA2/wildcard.le.test.pem")" "600"

echo ""
echo "certselect.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
