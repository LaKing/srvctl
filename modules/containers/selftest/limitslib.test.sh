#!/bin/bash
#
# modules/containers/selftest/limitslib.test.sh — per-container resource
# limit rendering and drop-in reconciliation. The datastore and systemctl
# are stubbed; drop-ins go to a temporary unit directory.
# Run: bash modules/containers/selftest/limitslib.test.sh

# Stubs are consumed by the sourced library.
# shellcheck disable=SC2034,SC2329
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

pass=0
fail=0
ok() {
    if [[ "$2" == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}

SC_LIMITS_UNIT_DIR="$(mktemp -d)"
trap 'rm -rf "$SC_LIMITS_UNIT_DIR"' EXIT

RECORD='{}'
ACTIVE=0
declare -a CALLS=()
msg() { :; }
err() { :; }
out() { printf '%s\n' "$RECORD"; }
run() { CALLS+=("$*"); }
systemctl() { [[ $1 == -q && $2 == is-active ]] && return "$ACTIVE"; CALLS+=("systemctl $*"); }

# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/limitslib.sh"

echo "validators"
container_limits_valid_cpu 400%; ok "cpu 400%" $? 0
container_limits_valid_cpu 0%; ok "cpu 0%" $? 1
container_limits_valid_cpu 400; ok "cpu no %" $? 1
container_limits_valid_cpu '4%;x'; ok "cpu junk" $? 1
container_limits_valid_memory 512M; ok "mem 512M" $? 0
container_limits_valid_memory 8g; ok "mem lowercase" $? 1
container_limits_valid_memory 8; ok "mem no suffix" $? 1

echo "rendering"
ok "all unset" "$(container_limits_config - - -)" ""
ok "cpu only" "$(container_limits_config 200% - - | tail -n +2)" $'[Service]\nCPUQuota=200%'
container_limits_config 200 - - > /dev/null; ok "invalid stored cpu" $? 22
container_limits_config - 8X - > /dev/null; ok "invalid stored memory" $? 22

echo "apply"
C=test.ve
file="$(container_limits_dropin "$C")"
RECORD='{"ip":"10.1.2.3","cpu_quota":"200%","memory_max":"4G"}'
CALLS=()
apply_container_limits "$C"; ok "apply rc" $? 0
ok "drop-in written" "$(grep -c '^CPUQuota=200%$\|^MemoryMax=4G$' "$file")" 2
ok "no MemoryHigh line" "$(grep -c MemoryHigh "$file")" 0
ok "reload + live update" "${CALLS[*]}" "systemctl daemon-reload systemctl set-property --runtime srvctl-nspawn@test.ve.service CPUQuota=200% MemoryMax=4G MemoryHigh=8G"

CALLS=()
apply_container_limits "$C"
ok "unchanged is a no-op" "${#CALLS[@]}" 0

ACTIVE=1
RECORD='{"ip":"10.1.2.3","cpu_quota":"300%"}'
CALLS=()
apply_container_limits "$C"
ok "stopped unit: reload only" "${CALLS[*]}" "systemctl daemon-reload"

ACTIVE=0
RECORD='{"ip":"10.1.2.3"}'
CALLS=()
apply_container_limits "$C"
ok "reset removes drop-in" "$([[ -e $file || -d ${file%/*} ]] && echo present || echo gone)" gone
ok "reset restores defaults live" "${CALLS[*]}" "systemctl daemon-reload systemctl set-property --runtime srvctl-nspawn@test.ve.service CPUQuota=800% MemoryMax=16G MemoryHigh=8G"

RECORD='{"cpu_quota":"lots"}'
CALLS=()
apply_container_limits "$C"; ok "bad stored value rc" $? 22
ok "bad stored value touches nothing" "${#CALLS[@]}" 0

echo "limitslib: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
