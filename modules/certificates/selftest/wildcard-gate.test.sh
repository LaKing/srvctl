#!/bin/bash
#
# modules/certificates/selftest/wildcard-gate.test.sh — the one wildcard rule.
#
# wildcardgatelib.sh decides both what certselect serves as a wildcard and
# whether a wildcard suppresses http-01 (letsencrypt). This test proves the
# rule on real openssl fixtures and under production conditions:
#   P1  the real load_libs from commonlib.sh loads the certificates libs in
#       their production glob order (certselectlib first, wildcardgatelib
#       last) and everything works; a reversed source order gives the same
#       results (nothing runs at load time).
#   P2  standalone: `env -i bash --noprofile --norc -u` with only the gate lib
#       sourced, no SRVCTL, no lablib — correct results and empty stderr,
#       with and without SC_DATASTORE_DIR.
#   P4  static allow-list: the gate lib calls nothing but its own functions,
#       bash builtins, openssl, date and basename.
# Consistency: the names covered by a wildcard that certselect actually
# installs equal the names wildcard_covering reports as covered.
#
# Run: bash modules/certificates/selftest/wildcard-gate.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
GATE="$REPO/modules/certificates/libs/wildcardgatelib.sh"

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# cert CN SAN(or -) DAYS OUT [not_before not_after]  — cert followed by key
cert() {
  local cn="$1" san="$2" days="$3" out="$4" nb="${5:-}" na="${6:-}" key crt
  local -a extra=()
  key="$(mktemp)"; crt="$(mktemp)"
  [[ "$san" != - ]] && extra+=(-addext "subjectAltName=$san")
  if [[ -n "$nb" ]]; then extra+=(-not_before "$nb" -not_after "$na"); else extra+=(-days "$days"); fi
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$key" -out "$crt" -subj "/CN=$cn" "${extra[@]}" > /dev/null 2>&1
  cat "$crt" "$key" > "$out"
  rm -f "$key" "$crt"
}
# bundle BASE DAYS OUT [not_before not_after] — key first, like a managed bundle
bundle() {
  local base="$1" days="$2" out="$3" nb="${4:-}" na="${5:-}" tmp
  tmp="$(mktemp)"
  cert "$base" "DNS:$base,DNS:*.$base" "$days" "$tmp" "$nb" "$na"
  { openssl pkey -in "$tmp"; openssl x509 -in "$tmp"; } > "$out" 2> /dev/null
  rm -f "$tmp"
}

ADMIN="$TMP/admin"; DS="$TMP/ds"; HA="$TMP/haproxy"
mkdir -p "$ADMIN"/{x.test,six.test,old.test,sanonly.test} "$DS/cert/wildcard" "$HA"
cert '*.x.test'       -                      30 "$ADMIN/x.test/x.test.pem"             # admin, 30 days
cert '*.six.test'     -                       6 "$ADMIN/six.test/six.test.pem"         # admin, < 7 days
cert '*.old.test'     - 1 "$ADMIN/old.test/old.test.pem" 20200101000000Z 20200102000000Z  # admin, expired
cert 'sanonly.test' 'DNS:sanonly.test,DNS:*.sanonly.test' 30 "$ADMIN/sanonly.test/sanonly.test.pem"  # SAN-only admin
bundle m.test 2 "$DS/cert/wildcard/m.test.pem"                                        # managed, 2 days
bundle short.test 1 "$DS/cert/wildcard/short.test.pem"                                # managed, < 1 day
bundle future.test 1 "$DS/cert/wildcard/future.test.pem" 20990101000000Z 20991231000000Z  # not yet valid
bundle other.test 30 "$DS/cert/wildcard/renamed.test.pem"                             # name != SAN base

DOMAINS="x.test a.x.test a.b.x.test six.test a.six.test old.test a.old.test sanonly.test a.sanonly.test m.test www.m.test a.b.m.test short.test future.test renamed.test other.test"
# expected: covered (c) or not (n), same order as DOMAINS
EXPECT="c c n n n n n n n c c n n n n n"
read -r -a DOMAIN_LIST <<< "$DOMAINS"

# gate_results: "<domain>=c|n ..." using wildcard_covering in the current shell
gate_results() {
  local d out=""
  for d in $DOMAINS; do
    if wildcard_covering "$d" > /dev/null; then out+="$d=c "; else out+="$d=n "; fi
  done
  echo "$out"
}
expected_results() {
  local out="" d
  local -a e
  read -r -a e <<< "$EXPECT"
  local i=0
  for d in $DOMAINS; do out+="$d=${e[$i]} "; i=$((i + 1)); done
  echo "$out"
}
WANT="$(expected_results)"

# --- P1: production load_libs, production order and reversed order ---------
p1() {
  local order="$1"
  (
    set +u
    export SRVCTL=1
    # shellcheck disable=SC2329 # called by the sourced libs
    debug() { :; }
    # shellcheck disable=SC2329
    msg() { :; }
    # shellcheck disable=SC2329
    err() { :; }
    # shellcheck disable=SC2329
    ntc() { :; }
    # shellcheck source=/dev/null
    source "$REPO/commonlib.sh"
    export SC_ADMIN_CERT_DIR="$ADMIN" SC_DATASTORE_DIR="$DS"
    if [[ $order == production ]]; then
      # shellcheck disable=SC2034 # read by load_libs
      SC_MODULES="$REPO/modules/certificates"
      # shellcheck disable=SC2034 # read by load_libs through ${!tvll}
      SC_USE_CERTIFICATES=true
      load_libs
    else
      local f
      local -a libs=("$REPO"/modules/certificates/libs/*)
      for ((f = ${#libs[@]} - 1; f >= 0; f--)); do
        # shellcheck source=/dev/null
        source "${libs[$f]}"
      done
    fi
    rm -rf "$HA"; mkdir -p "$HA"
    sync_haproxy_certificates "$HA"
    echo "$(gate_results)|$(cd "$HA" && ls)"
  )
}
prod="$(p1 production)"
rev="$(p1 reversed)"
ok "P1 load_libs order: gate results" "${prod%%|*}" "$WANT"
ok "P1 reversed source order: same results" "$rev" "$prod"
ok "P1 load order in production is glob order, gate lib last" \
  "$(libs=("$REPO"/modules/certificates/libs/*); echo "${libs[-1]##*/}")" "wildcardgatelib.sh"

# --- consistency: served wildcard set == gate ------------------------------
consistency() {
  (
    set +u
    # shellcheck source=/dev/null
    source "$GATE"
    local f base bases="" d out=""
    for f in "$HA"/*.pem; do
      case "${f##*/}" in
        wildcard.*) base="${f##*/wildcard.}"; base="${base%.pem}" ;;
        *) base="$(check_wildcard_pem "$f")" ;;
      esac
      [[ "$base" == false ]] || bases+=" $base"
    done
    for d in $DOMAINS; do
      local c=n b
      for b in $bases; do domain_under_wildcard "$d" "$b" && c=c; done
      out+="$d=$c "
    done
    echo "$out"
  )
}
# HA holds the result of the last P1 run (reversed order)
ok "certselect served set equals the gate" "$(consistency)" "$WANT"

# --- P2: standalone, empty environment, set -u --------------------------------
p2() {
  local ds="$1" errf="$TMP/p2.err"
  local -a envs=(PATH="$PATH" SC_ADMIN_CERT_DIR="$ADMIN")
  [[ -n "$ds" ]] && envs+=(SC_DATASTORE_DIR="$ds")
  # shellcheck disable=SC2016 # expanded by the inner bash
  env -i "${envs[@]}" bash --noprofile --norc -uc '
    source "$1"; shift
    for d in "$@"; do
      if wildcard_covering "$d" > /dev/null; then printf "%s=c " "$d"; else printf "%s=n " "$d"; fi
    done' _ "$GATE" "${DOMAIN_LIST[@]}" 2> "$errf"
  echo
  echo "stderr:$(cat "$errf")"
}
out="$(p2 "$DS")"
ok "P2 standalone gate results" "$(head -1 <<< "$out")" "$WANT"
ok "P2 standalone stderr empty" "$(tail -1 <<< "$out")" "stderr:"
out="$(p2 "")"
ok "P2 without SC_DATASTORE_DIR: admin only" "$(head -1 <<< "$out")" \
  "x.test=c a.x.test=c a.b.x.test=n six.test=n a.six.test=n old.test=n a.old.test=n sanonly.test=n a.sanonly.test=n m.test=n www.m.test=n a.b.m.test=n short.test=n future.test=n renamed.test=n other.test=n "
ok "P2 without SC_DATASTORE_DIR: stderr empty" "$(tail -1 <<< "$out")" "stderr:"

# batch variant agrees with the single-name function
# shellcheck disable=SC2016 # expanded by the inner bash
many="$(env -i PATH="$PATH" SC_ADMIN_CERT_DIR="$ADMIN" SC_DATASTORE_DIR="$DS" bash --noprofile --norc -uc \
  'source "$1"; wildcard_covering_many' _ "$GATE" < <(tr ' ' '\n' <<< "$DOMAINS") 2> "$TMP/many.err" \
  | awk -F'\t' '{printf "%s=%s ", $1, ($2 == "-" ? "n" : "c")}')"
ok "wildcard_covering_many agrees" "$many" "$WANT"
ok "wildcard_covering_many stderr empty" "$(cat "$TMP/many.err")" ""
# shellcheck disable=SC2016 # expanded by the inner bash
ok "SC_WILDCARD_EXCLUDE leaves one file out" \
  "$(env -i PATH="$PATH" SC_ADMIN_CERT_DIR="$ADMIN" SC_DATASTORE_DIR="$DS" SC_WILDCARD_EXCLUDE="$DS/cert/wildcard/m.test.pem" \
     bash --noprofile --norc -uc 'source "$1"; wildcard_covering www.m.test || echo none' _ "$GATE")" "none"

# --- P4: allow-list --------------------------------------------------------
# Enforced, not grepped: run the gate with PATH holding nothing but openssl,
# date and basename. Any other external command (or a helper from another
# srvctl file) fails with "command not found" on stderr.
mkdir -p "$TMP/bin"
for c in openssl date basename; do ln -s "$(command -v "$c")" "$TMP/bin/$c"; done
# shellcheck disable=SC2016 # expanded by the inner bash
out="$(env -i PATH="$TMP/bin" SC_ADMIN_CERT_DIR="$ADMIN" SC_DATASTORE_DIR="$DS" /bin/bash --noprofile --norc -uc '
  source "$1"; shift
  for d in "$@"; do
    if wildcard_covering "$d" > /dev/null; then printf "%s=c " "$d"; else printf "%s=n " "$d"; fi
  done' _ "$GATE" "${DOMAIN_LIST[@]}" 2> "$TMP/p4.err")"
ok "P4 gate runs with only openssl/date/basename on PATH" "$out" "$WANT"
ok "P4 no command-not-found / unbound variable" "$(cat "$TMP/p4.err")" ""
ok "P4 no lablib or certselect helpers referenced" \
  "$(grep -vE '^[[:space:]]*#' "$GATE" | grep -cE '(^|[^a-z_])(msg|err|ntc|debug|run|cert_valid|cert_notafter_epoch|cert_newer)([^a-z_]|$)')" "0"
ok "P4 nothing but function definitions at load time" \
  "$(grep -vE '^[[:space:]]*(#|$)' "$GATE" | grep -cvE '^(function |[[:space:]]|\})')" "0"
if command -v shellcheck > /dev/null; then
  ok "P4 shellcheck" "$(shellcheck "$GATE" > /dev/null 2>&1 && echo clean || echo dirty)" "clean"
fi

echo ""
echo "wildcard-gate.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
