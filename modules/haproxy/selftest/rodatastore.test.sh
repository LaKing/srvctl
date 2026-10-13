#!/bin/bash
#
# modules/haproxy/selftest/rodatastore.test.sh — regenerate_haproxy_conf with
# a read-only datastore.
#
# regenerate_haproxy_conf (libs/proxylib.sh) against a temporary datastore;
# msg/err, the certificate sync, haproxycfg and the reload are stubbed, and
# the host dirs /var/haproxy and /etc/srvctl/cert are not created:
#   unwritable  (missing cert dir under a read-only datastore, or an existing
#               read-only cert dir as in the gluster copy) exactly one err
#               naming the resolved dirs, nothing created, and the sync,
#               haproxycfg and the reload still run
#   partly      (read-only cert dir under a writable datastore, writable cert
#               dir under a read-only datastore, a file in the way of
#               pki-validation) one err naming only the dir that failed, the
#               other dir is still created
#   writable    no err, and the same tree (names and modes) as the plain
#               mkdir -p calls, existing certificates untouched
# chmod a-w does not stop root, so as root the test re-runs itself as nobody.
#
# Run: bash modules/haproxy/selftest/rodatastore.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

if [[ $EUID == 0 ]]
then
    exec setpriv --reuid=nobody --regid=nobody --clear-groups bash "$REPO/modules/haproxy/selftest/rodatastore.test.sh"
fi

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP"; rm -rf "$TMP"' EXIT

ERRS="$TMP/errs"
STEPS="$TMP/steps"
# shellcheck disable=SC2329 # stubs called by the sourced lib
msg() { :; }
# shellcheck disable=SC2329
err() { echo "$*" >> "$ERRS"; }
# shellcheck disable=SC2329
mkdir() {
    case " $* " in
        *" /var/haproxy "* | *" /etc/srvctl/cert "*) return 0 ;;
    esac
    command mkdir "$@"
}
# shellcheck disable=SC2329
sync_haproxy_certificates() { echo sync >> "$STEPS"; }
# shellcheck disable=SC2329
haproxycfg() { echo haproxycfg >> "$STEPS"; }
# shellcheck disable=SC2329
reload_haproxy() { echo reload >> "$STEPS"; }
# shellcheck source=/dev/null
source "$REPO/modules/haproxy/libs/proxylib.sh"
# shellcheck disable=SC2329 # replaces the one proxylib.sh defines
haproxy_record_reloaded() { :; }

# shellcheck disable=SC2034 # ARG is read by regenerate_haproxy_conf
run_regenerate() {
    SC_DATASTORE_DIR="$1" ARG=""
    : > "$ERRS"; : > "$STEPS"
    regenerate_haproxy_conf > /dev/null 2> "$TMP/stderr"
}
tree() { (cd "$1" && find . -printf '%p %m %s\n' | LC_ALL=C sort); }

## unwritable: no cert dir yet, datastore read-only
command mkdir -p "$TMP/ro"
chmod a-w "$TMP/ro"
ok "read-only datastore really is unwritable" "$(touch "$TMP/ro/probe" 2> /dev/null && echo writable || echo unwritable)" "unwritable"
before="$(tree "$TMP/ro")"
run_regenerate "$TMP/ro"
ok "missing cert dir: exactly one err" "$(wc -l < "$ERRS")" "1"
ok "missing cert dir: err names the resolved paths" "$(cat "$ERRS")" "Datastore dir not writable, skipped: $TMP/ro/cert $TMP/ro/pki-validation"
ok "missing cert dir: nothing created" "$(tree "$TMP/ro")" "$before"
ok "missing cert dir: no stray stderr" "$(cat "$TMP/stderr")" ""
ok "missing cert dir: rest of the configuration proceeds" "$(paste -sd' ' "$STEPS")" "sync haproxycfg reload"

## unwritable: the gluster copy, cert dir present but read-only
command mkdir -p "$TMP/gl/cert"
echo cert-a > "$TMP/gl/cert/a.pem"
chmod -R a-w "$TMP/gl"
before="$(tree "$TMP/gl")"
run_regenerate "$TMP/gl"
ok "read-only cert dir: exactly one err" "$(wc -l < "$ERRS")" "1"
ok "read-only cert dir: err names the resolved paths" "$(cat "$ERRS")" "Datastore dir not writable, skipped: $TMP/gl/cert $TMP/gl/pki-validation"
ok "read-only cert dir: no pki-validation, nothing changed" "$(tree "$TMP/gl")" "$before"
ok "read-only cert dir: rest of the configuration proceeds" "$(paste -sd' ' "$STEPS")" "sync haproxycfg reload"

## partly: read-only cert dir, writable datastore
command mkdir -p "$TMP/pc/cert"
chmod a-w "$TMP/pc/cert"
run_regenerate "$TMP/pc"
ok "read-only cert dir only: one err naming it" "$(cat "$ERRS")" "Datastore dir not writable, skipped: $TMP/pc/cert"
ok "read-only cert dir only: pki-validation still created" "$([[ -d "$TMP/pc/pki-validation" ]] && echo yes || echo no)" "yes"
ok "read-only cert dir only: rest of the configuration proceeds" "$(paste -sd' ' "$STEPS")" "sync haproxycfg reload"

## partly: writable cert dir, read-only datastore
command mkdir -p "$TMP/pp/cert"
chmod a-w "$TMP/pp"
run_regenerate "$TMP/pp"
ok "read-only datastore, writable cert dir: one err naming pki-validation" "$(cat "$ERRS")" "Datastore dir not writable, skipped: $TMP/pp/pki-validation"
ok "read-only datastore, writable cert dir: no stray stderr" "$(cat "$TMP/stderr")" ""
ok "read-only datastore, writable cert dir: rest of the configuration proceeds" "$(paste -sd' ' "$STEPS")" "sync haproxycfg reload"

## partly: a file in the way of pki-validation
command mkdir -p "$TMP/pf"
echo not-a-dir > "$TMP/pf/pki-validation"
run_regenerate "$TMP/pf"
ok "pki-validation obstructed: one err naming it" "$(cat "$ERRS")" "Datastore dir not writable, skipped: $TMP/pf/pki-validation"
ok "pki-validation obstructed: cert dir still created" "$([[ -d "$TMP/pf/cert" ]] && echo yes || echo no)" "yes"
ok "pki-validation obstructed: the file is untouched" "$(cat "$TMP/pf/pki-validation")" "not-a-dir"
ok "pki-validation obstructed: rest of the configuration proceeds" "$(paste -sd' ' "$STEPS")" "sync haproxycfg reload"

## writable: same result as the plain mkdir -p calls
command mkdir -p "$TMP/ref"
command mkdir -p "$TMP/ref/cert"
command mkdir -p "$TMP/ref/pki-validation"
run_regenerate "$TMP/rw"
ok "writable, fresh: no err" "$(cat "$ERRS")" ""
ok "writable, fresh: same tree as before" "$(tree "$TMP/rw")" "$(tree "$TMP/ref")"
ok "writable, fresh: rest of the configuration proceeds" "$(paste -sd' ' "$STEPS")" "sync haproxycfg reload"

echo cert-a > "$TMP/rw/cert/a.pem"
echo cert-a > "$TMP/ref/cert/a.pem"
run_regenerate "$TMP/rw"
ok "writable, existing: no err" "$(cat "$ERRS")" ""
ok "writable, existing: same tree as before" "$(tree "$TMP/rw")" "$(tree "$TMP/ref")"
ok "writable, existing: certificate byte-identical" "$(cmp -s "$TMP/rw/cert/a.pem" "$TMP/ref/cert/a.pem" && echo same || echo differs)" "same"

echo ""
echo "rodatastore.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
