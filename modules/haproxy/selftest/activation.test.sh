#!/bin/bash
#
# modules/haproxy/selftest/activation.test.sh — renewed certificates become
# active without manual action, and a crash cannot lose a reload.
#
# regenerate_haproxy_conf (libs/proxylib.sh) with the REAL reload_haproxy /
# restart_haproxy (libs/systemdlib.sh); only the certificate sync, haproxycfg,
# the systemctl/haproxy binaries and sleep are stubbed:
#   manual run            always reloads and records what haproxy serves
#   hourly cron, same set no reload (as before)
#   hourly cron, changed  reloads (a renewal or a new wildcard)
#   reload not confirmed  (haproxy inactive afterwards and the restart fails,
#                         a failed reload while the old process stays active,
#                         or a crash between the sync and the reload) the
#                         record keeps the old set, so the next cron run
#                         reloads again
# The record lives outside the crt directory haproxy loads whole.
#
# Run: bash modules/haproxy/selftest/activation.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export SC_DATASTORE_DIR="$TMP/ds" SC_HAPROXY_CERT_DIR="$TMP/haproxy" SC_HAPROXY_RELOADED_LIST="$TMP/acme/haproxy-reloaded.list"
mkdir -p "$SC_HAPROXY_CERT_DIR"
RELOADS=0          # systemctl reload attempts
ACTIVE=yes         # unit state as systemctl is-active reports it
RELOAD_OK=yes      # whether systemctl reload succeeds
RESTART_OK=yes     # whether systemctl restart leaves the unit active
# shellcheck disable=SC2329 # stubs called by the sourced libs
msg() { :; }
# shellcheck disable=SC2329
err() { :; }
# shellcheck disable=SC2329
run() { :; }
# shellcheck disable=SC2329
haproxy() { :; }
# shellcheck disable=SC2329
mkdir() { command mkdir "$@" 2> /dev/null || true; }
# shellcheck disable=SC2329
sync_haproxy_certificates() { :; }
# shellcheck disable=SC2329
haproxycfg() { :; }
# shellcheck disable=SC2329
systemctl() {
    case "$1" in
        reload) RELOADS=$((RELOADS + 1)); [[ $RELOAD_OK == yes ]] ;;
        restart) [[ $RESTART_OK == yes ]] && ACTIVE=yes; [[ $RESTART_OK == yes ]] ;;
        is-active) [[ $ACTIVE == yes ]] ;;
        *) return 0 ;;
    esac
}
# shellcheck source=/dev/null
source "$REPO/modules/haproxy/libs/systemdlib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/haproxy/libs/proxylib.sh"

# shellcheck disable=SC2034 # ARG is read by regenerate_haproxy_conf
run_regenerate() { ARG="$1"; regenerate_haproxy_conf > /dev/null; }

echo cert-a > "$SC_HAPROXY_CERT_DIR/a.pem"
run_regenerate "#cron.hourly"
ok "cron, nothing recorded yet: reload" "$RELOADS" "1"
ok "record written outside the crt dir" "$([[ -f "$SC_HAPROXY_RELOADED_LIST" && "$SC_HAPROXY_RELOADED_LIST" != "$SC_HAPROXY_CERT_DIR"/* ]] && echo yes || echo no)" "yes"

run_regenerate "#cron.hourly"
ok "cron, same certificate set: no reload" "$RELOADS" "1"

echo cert-a-renewed > "$SC_HAPROXY_CERT_DIR/a.pem"
run_regenerate "#cron.hourly"
ok "cron, renewed certificate: reload" "$RELOADS" "2"

echo wildcard > "$SC_HAPROXY_CERT_DIR/wildcard.x.test.pem"
ACTIVE=no RESTART_OK=no
run_regenerate "#cron.hourly"
ok "cron, new wildcard: reload" "$RELOADS" "3"
ok "reload left haproxy inactive, restart failed: not recorded" "$(haproxy_certificates_changed && echo changed || echo same)" "changed"
RESTART_OK=yes
run_regenerate "#cron.hourly"
ok "reload not confirmed last time: reloads again" "$RELOADS" "4"
run_regenerate "#cron.hourly"
ok "then quiet again" "$RELOADS" "4"

# the common failure: the reload fails while the old process stays active
echo cert-a-renewed-again > "$SC_HAPROXY_CERT_DIR/a.pem"
RELOAD_OK=no
run_regenerate "#cron.hourly"
ok "failed reload, old haproxy still active: attempted" "$RELOADS" "5"
ok "failed reload, old haproxy still active: not recorded" "$(haproxy_certificates_changed && echo changed || echo same)" "changed"
run_regenerate "#cron.hourly"
ok "failed reload is retried on the next hourly run" "$RELOADS" "6"
RELOAD_OK=yes
run_regenerate "#cron.hourly"
ok "retry succeeds" "$RELOADS" "7"
run_regenerate "#cron.hourly"
ok "then quiet again after the successful reload" "$RELOADS" "7"
# (subshells: these two do not count in RELOADS)
ok "reload_haproxy reports a failed reload" "$(RELOAD_OK=no; reload_haproxy && echo ok || echo failed)" "failed"
ok "reload_haproxy reports a successful reload" "$(reload_haproxy && echo ok || echo failed)" "ok"

# a crash after the sync changed the set but before the reload: the record
# still holds the old set
echo cert-b > "$SC_HAPROXY_CERT_DIR/b.pem"
run_regenerate "#cron.hourly"
ok "set changed without a recorded reload: next cron run reloads" "$RELOADS" "8"

run_regenerate ""
ok "manual run always reloads" "$RELOADS" "9"

echo ""
echo "activation.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
