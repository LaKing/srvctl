#!/bin/bash
#
# modules/named/selftest/systemdlib.test.sh — safe propagation regression.
#
# Sources the real named systemd library but stubs named-checkconf, systemctl,
# rndc, SOA queries and sleep. No service, BIND process, configuration or
# network is touched.
# Run: bash modules/named/selftest/systemdlib.test.sh

# Command doubles below are invoked indirectly by functions sourced from the
# production library.
# shellcheck disable=SC2329
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

# The library only defines functions; command dependencies are replaced below.
# shellcheck source=/dev/null
source "$REPO/modules/named/libs/systemdlib.sh"

pass=0
fail=0
RC=0
MARKS=""

ok() {
    if [[ $2 == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}

count_mark() {
    local needle count=0 line
    needle="$1"
    while IFS= read -r line
    do
        [[ $line == "$needle" ]] && count=$((count + 1))
    done <<< "$MARKS"
    echo "$count"
}

has_mark() {
    local needle line
    needle="$1"
    while IFS= read -r line
    do
        [[ $line == "$needle" ]] && { echo yes; return; }
    done <<< "$MARKS"
    echo no
}

line_number() {
    local needle line number=0
    needle="$1"
    while IFS= read -r line
    do
        number=$((number + 1))
        [[ $line == "$needle" ]] && { echo "$number"; return; }
    done <<< "$MARKS"
    echo 0
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CONF="$TMP/srvctl.conf"
cat > "$CONF" <<'EOF'
## generated test configuration
zone "master.example" {type master; file "/tmp/master.zone";};
  zone "slave.example" { type slave; masters {192.0.2.1;}; };
// zone "commented.example" {type master;};
zone "hint.example" {type hint; file "named.ca";};
zone "master-two.example" {type master; file "/tmp/master-two.zone";};
zone "slave-two.example" {type slave; primaries {198.51.100.2;}; file "/tmp/slave-two.zone";};
EOF

# Direct parser coverage is independent of the orchestration command stubs.
PARSED="$(named_managed_zones "$CONF")"
EXPECTED=$'master\tmaster.example\nslave\tslave.example\t192.0.2.1\nmaster\tmaster-two.example\nslave\tslave-two.example\t198.51.100.2'
ok "managed-zone parser" "$PARSED" "$EXPECTED"

# Exercise the production dig-response parser without contacting a server.
QUERY_SERIAL="$({
    dig() { printf '%s\n' 'ns.example. hostmaster.example. 4242 3600 600 86400 300'; }
    queried_serial=""
    named_query_soa_serial queried_serial 192.0.2.1 slave.example || exit 1
    printf '%s' "$queried_serial"
})"
ok "SOA parser returns numeric serial" "$QUERY_SERIAL" "4242"

if (
    dig() { printf '%s\n' 'not-an-soa'; }
    queried_serial=""
    named_query_soa_serial queried_serial 192.0.2.1 slave.example
)
then
    BAD_SOA_RC=0
else
    BAD_SOA_RC=$?
fi
ok "invalid SOA response fails" "$BAD_SOA_RC" "1"

probe() {
    local markfile
    markfile="$(mktemp "$TMP/marks.XXXXXX")"

    (
        PREFLIGHT_RC="${PREFLIGHT_RC:-0}"
        RESTART_RC="${RESTART_RC:-0}"
        READY_AFTER="${READY_AFTER:-1}"
        NOTIFY_FAIL_ZONE="${NOTIFY_FAIL_ZONE:-}"
        RETRANSFER_FAIL_ZONE="${RETRANSFER_FAIL_ZONE:-}"
        SOA_MODE="${SOA_MODE:-converged}"
        # shellcheck disable=SC2034 # consumed by the sourced production function
        NAMED_FORCE_RETRANSFER="${FORCE_RETRANSFER:-true}"
        # shellcheck disable=SC2034 # consumed by the sourced production function
        NAMED_REPLICA_TIMEOUT_SECONDS="${CONVERGENCE_TIMEOUT_SECONDS:-3}"
        rndc_status_calls=0
        fake_now=0
        declare -A soa_calls=()

        mark() { printf '%s\n' "$*" >> "$markfile"; }
        msg() { mark "msg $*"; }
        err() { mark "err $*"; }
        named-checkconf() { mark "named-checkconf $*"; return "$PREFLIGHT_RC"; }
        named_monotonic_seconds() { printf '%s\n' "$fake_now"; }
        sleep() {
            mark "sleep $*"
            fake_now=$((fake_now + $1))
        }
        systemctl() {
            mark "systemctl $*"
            if [[ $1 == restart ]]
            then
                return "$RESTART_RC"
            fi
            return 0
        }
        rndc() {
            mark "rndc $*"
            case "$1" in
                status)
                    rndc_status_calls=$((rndc_status_calls + 1))
                    (( rndc_status_calls >= READY_AFTER ))
                    ;;
                notify)
                    [[ $2 != "$NOTIFY_FAIL_ZONE" ]]
                    ;;
                retransfer)
                    [[ $2 != "$RETRANSFER_FAIL_ZONE" ]]
                    ;;
                *)
                    return 0
                    ;;
            esac
        }
        named_query_soa_serial() {
            local result_variable server zone key call serial
            result_variable="$1"
            server="$2"
            zone="$3"
            key="$server|$zone"
            call=$(( ${soa_calls[$key]:-0} + 1 ))
            soa_calls["$key"]="$call"
            mark "soa $server $zone"

            if [[ $zone == slave-two.example ]]
            then
                case "$SOA_MODE:$server" in
                    queued:127.0.0.1)
                        if (( call < 2 )); then serial=100; else serial=300; fi
                        ;;
                    *)
                        serial=300
                        ;;
                esac
            else
                case "$SOA_MODE:$server" in
                    delayed:127.0.0.1)
                        if (( call < 3 )); then serial=100; else serial=200; fi
                        ;;
                    queued:127.0.0.1)
                        if (( call < 4 )); then serial=100; else serial=200; fi
                        ;;
                    mismatch:127.0.0.1)
                        serial=100
                        ;;
                    query_failure:192.0.2.1)
                        return 1
                        ;;
                    *)
                        serial=200
                        ;;
                esac
            fi

            printf -v "$result_variable" '%s' "$serial"
        }

        restart_named "$CONF"
    ) > /dev/null 2>&1
    RC=$?
    MARKS="$(<"$markfile")"
    rm -f "$markfile"
}

PREFLIGHT_RC=1 probe
ok "preflight failure returns nonzero" "$RC" "1"
ok "preflight loads primary zones" "$(has_mark 'named-checkconf -z')" "yes"
ok "preflight failure never restarts" "$(has_mark 'systemctl restart named.service')" "no"
ok "preflight failure is visible" "$(has_mark 'err named configuration preflight FAILED!')" "yes"

PREFLIGHT_RC=0 RESTART_RC=1 probe
ok "restart failure returns nonzero" "$RC" "1"
ok "restart was attempted" "$(has_mark 'systemctl restart named.service')" "yes"
ok "restart failure prints status" "$(has_mark 'systemctl status named.service --no-pager')" "yes"
ok "restart failure does not propagate" "$(count_mark 'rndc notify master.example')" "0"
ok "restart failure does not retransfer" "$(count_mark 'rndc retransfer slave.example')" "0"

RESTART_RC=0 READY_AFTER=3 probe
ok "eventual rndc readiness succeeds" "$RC" "0"
ok "readiness is polled" "$(count_mark 'rndc status')" "3"
ok "readiness waits only between attempts" "$(count_mark 'sleep 1')" "2"
ok "master gets notify" "$(has_mark 'rndc notify master.example')" "yes"
ok "second master gets notify" "$(has_mark 'rndc notify master-two.example')" "yes"
ok "slave gets retransfer" "$(has_mark 'rndc retransfer slave.example')" "yes"
ok "primaries slave gets retransfer" "$(has_mark 'rndc retransfer slave-two.example')" "yes"
ok "legacy refresh is not used" "$(count_mark 'rndc refresh slave.example')" "0"
ok "commented zone ignored" "$(has_mark 'rndc notify commented.example')" "no"
ok "hint zone ignored" "$(has_mark 'rndc notify hint.example')" "no"
ok "restart precedes propagation" "$(( $(line_number 'systemctl restart named.service') < $(line_number 'rndc notify master.example') ))" "1"
ok "readiness precedes propagation" "$(( $(line_number 'rndc status') < $(line_number 'rndc notify master.example') ))" "1"

READY_AFTER=99 probe
ok "readiness timeout returns nonzero" "$RC" "1"
ok "readiness timeout is bounded" "$(count_mark 'rndc status')" "10"
ok "bounded wait has nine sleeps" "$(count_mark 'sleep 1')" "9"
ok "timeout prints service status" "$(has_mark 'systemctl status named.service --no-pager')" "yes"
ok "timeout does not propagate" "$(count_mark 'rndc retransfer slave.example')" "0"

READY_AFTER=1 NOTIFY_FAIL_ZONE=master.example RETRANSFER_FAIL_ZONE=slave.example probe
ok "zone failures aggregate to nonzero" "$RC" "1"
ok "failed notify is visible" "$(has_mark 'err rndc notify FAILED for zone master.example')" "yes"
ok "failed retransfer is visible" "$(has_mark 'err rndc retransfer FAILED for zone slave.example')" "yes"
ok "later zones still run" "$(has_mark 'rndc notify master-two.example')" "yes"
ok "later replicas still run" "$(has_mark 'rndc retransfer slave-two.example')" "yes"

FORCE_RETRANSFER=false probe
ok "hourly refresh mode succeeds" "$RC" "0"
ok "hourly mode refreshes first replica" "$(has_mark 'rndc refresh slave.example')" "yes"
ok "hourly mode refreshes later replica" "$(has_mark 'rndc refresh slave-two.example')" "yes"
ok "hourly mode does not force retransfer" "$(count_mark 'rndc retransfer slave.example')" "0"
ok "hourly mode does not claim verified convergence" "$(count_mark 'soa 127.0.0.1 slave.example')" "0"

SOA_MODE=delayed probe
ok "delayed convergence succeeds" "$RC" "0"
ok "delayed replica is polled until equal" "$(count_mark 'soa 127.0.0.1 slave.example')" "3"
ok "delayed primary is polled alongside replica" "$(count_mark 'soa 192.0.2.1 slave.example')" "3"
ok "delayed convergence waits between polls" "$(count_mark 'sleep 1')" "2"
ok "already converged replica leaves pending set" \
    "$(count_mark 'soa 127.0.0.1 slave-two.example')" "1"

CONVERGENCE_TIMEOUT_SECONDS=5 SOA_MODE=queued probe
ok "queued out-of-order convergence succeeds" "$RC" "0"
ok "later queued replica can finish first" \
    "$(count_mark 'soa 127.0.0.1 slave-two.example')" "2"
ok "first queued replica retains the global deadline" \
    "$(count_mark 'soa 127.0.0.1 slave.example')" "4"
ok "queued convergence uses one global polling clock" "$(count_mark 'sleep 1')" "3"

SOA_MODE=mismatch probe
ok "SOA mismatch returns nonzero" "$RC" "1"
ok "SOA mismatch polling is globally bounded" "$(count_mark 'soa 127.0.0.1 slave.example')" "4"
ok "SOA mismatch queries the primary each time" "$(count_mark 'soa 192.0.2.1 slave.example')" "4"
ok "SOA mismatch stops at the global deadline" "$(count_mark 'sleep 1')" "3"
ok "SOA mismatch is visible" \
    "$(has_mark 'err Replica SOA did not converge for zone slave.example (primary 200, local 100)')" "yes"
ok "all retransfers precede convergence polling" \
    "$(( $(line_number 'rndc retransfer slave-two.example') < $(line_number 'soa 192.0.2.1 slave.example') ))" "1"
ok "later replica is still verified" "$(count_mark 'soa 198.51.100.2 slave-two.example')" "1"
ok "converged replica is not reported at global timeout" \
    "$(has_mark 'err Replica SOA did not converge for zone slave-two.example (primary 300, local 300)')" "no"

SOA_MODE=query_failure probe
ok "SOA query failure returns nonzero" "$RC" "1"
ok "failed primary query is retried within global bound" "$(count_mark 'soa 192.0.2.1 slave.example')" "4"
ok "local SOA is still queried" "$(count_mark 'soa 127.0.0.1 slave.example')" "4"
ok "SOA query failure stops at global deadline" "$(count_mark 'sleep 1')" "3"
ok "SOA query failure is visible" \
    "$(has_mark 'err Could not verify replica SOA for zone slave.example against primary 192.0.2.1')" "yes"
ok "query failure does not skip later replica" "$(count_mark 'soa 198.51.100.2 slave-two.example')" "1"

# Default deadline scales by the largest queue sharing one primary: five zones
# at BIND's default two transfers-per-ns require three transfer batches.
SCALED_TIMEOUT="$({
    unset NAMED_REPLICA_TIMEOUT_SECONDS NAMED_REPLICA_MAX_SECONDS
    timeout=""
    named_replica_convergence_timeout timeout \
        $'one.example\t192.0.2.1' $'two.example\t192.0.2.1' \
        $'three.example\t192.0.2.1' $'four.example\t192.0.2.1' \
        $'five.example\t192.0.2.1' $'other.example\t198.51.100.2'
    printf '%s' "$timeout"
})"
ok "default convergence deadline scales for BIND transfer queue" "$SCALED_TIMEOUT" "25"

CAPPED_TIMEOUT="$({
    unset NAMED_REPLICA_TIMEOUT_SECONDS
    # shellcheck disable=SC2034 # consumed by the sourced production function
    NAMED_REPLICA_MAX_SECONDS=20
    timeout=""
    named_replica_convergence_timeout timeout \
        $'one.example\t192.0.2.1' $'two.example\t192.0.2.1' \
        $'three.example\t192.0.2.1' $'four.example\t192.0.2.1' \
        $'five.example\t192.0.2.1'
    printf '%s' "$timeout"
})"
ok "scaled convergence deadline remains capped" "$CAPPED_TIMEOUT" "20"

MISSING="$TMP/missing.conf"
MARKFILE="$TMP/missing.marks"
: > "$MARKFILE"
err() { printf 'err %s\n' "$*" >> "$MARKFILE"; }
if named_managed_zones "$MISSING" > /dev/null
then
    MISSING_RC=0
else
    MISSING_RC=$?
fi
ok "missing managed config fails" "$MISSING_RC" "1"
ok "missing managed config is visible" "$(<"$MARKFILE")" "err Cannot read managed named configuration $MISSING"

echo ""
echo "systemdlib.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
