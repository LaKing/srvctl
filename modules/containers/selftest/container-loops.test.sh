#!/bin/bash
#
# modules/containers/selftest/container-loops.test.sh — the regenerate loops
# that walk every container read the datastore once, through list. The
# datastore and the container builders are stubbed.
# Run: bash modules/containers/selftest/container-loops.test.sh

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

HOSTNAME=node1
SC_INSTALL_DIR="$REPO"
ROWS=""
LIST_CALLS="$(mktemp)"
trap 'rm -f "$LIST_CALLS"' EXIT
declare -a CALLS=() ERRORS=()

msg() { :; }
err() { ERRORS+=("$*"); }
## list runs in a process substitution, so it counts its calls in a file.
list() { echo "$*" >> "$LIST_CALLS"; printf '%s' "$ROWS"; }
get() { CALLS+=("get $*"); }
create_container_configuration_files() { CALLS+=("files $1"); cat > /dev/null; }
create_nspawn_container_filesystem() { CALLS+=("filesystem $1"); }
create_nspawn_container_config() { CALLS+=("config $1"); }

# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/regenlib.sh"

## Names that cannot exist under /srv on the machine running the test.
A="selftest-a.invalid"
B="selftest-b.invalid"
D="selftest-d.invalid"

echo "check_container_database"
ROWS="$A"$'\t'"node1"$'\n'"$B"$'\t'"node2"$'\n'"$D"$'\t'"node1"$'\n'
check_container_database < <(echo "stdin of the caller")
ok "creates the containers of this host only, and the body cannot swallow rows" "${CALLS[*]}" "files $A filesystem $A config $A files $D filesystem $D config $D"
ok "reads the datastore once" "$(cat "$LIST_CALLS")" "container host"

echo "check_container_ownership"
: > "$LIST_CALLS"
CALLS=()
ERRORS=()
ROWS="$A"$'\t'"true"$'\n'"$B"$'\t'"false"$'\n'"$D"$'\t'"-"$'\n'
check_container_ownership
ok "reports the mismatch only" "${#ERRORS[@]}" 1
ok "names the container and the repair" "$([[ ${ERRORS[0]} == "$B: "*"repair_container_ownership $B" ]] && echo yes)" yes
ok "repairs nothing on its own" "${#CALLS[@]}" 0
ok "reads the datastore once" "$(cat "$LIST_CALLS")" "container user_ip_match"

echo ""
echo "container-loops.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
