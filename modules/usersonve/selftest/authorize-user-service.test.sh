#!/bin/bash
# authorize-user-service: one polkit rule per user and unit, listed and removed
# again; bad names and unknown users or units are refused before any write.
set -uo pipefail
SC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cmd="$SC_INSTALL_DIR/modules/usersonve/commands/authorize-user-service.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export SC_POLKIT_RULES_DIR="$tmp/rules"

## runs the command as srvctl's run_command would: sourced, with ARG/OPA/SC_ARGV set
sc() {
    (
        # shellcheck disable=SC2034 # read by the sourced command
        SRVCTL='test' ARG="${2:-}" OPA="${3:-}" SC_ARGV=("$@")
        ve_only() { :; }
        root_only() { :; }
        argument() { [[ -n $ARG ]] || { echo "missing $1"; exit 32; }; }
        msg() { echo "$*"; }
        err() { echo "ERR $*"; }
        run() { "$@"; }
        id() { [[ $2 == codepad || $2 == web-dev ]]; }
        rpm() { :; }
        systemctl() { [[ $1 == show ]] && { [[ $5 == devpanel.service || $5 == app@1.service ]] && echo loaded || echo not-found; }; return 0; }
        # shellcheck source=modules/usersonve/commands/authorize-user-service.sh
        source "$cmd"
    )
}
expect() {
    [[ $2 == "$3" ]] || { echo "FAIL $1: expected '$2', got '$3'"; exit 1; }
    echo "PASS $1"
}
rule="$SC_POLKIT_RULES_DIR/60-srvctl-codepad-devpanel.rules"

sc authorize-user-service codepad devpanel > /dev/null
expect 'rule written, .service added' yes "$([[ -f $rule ]] && echo yes || echo no)"
expect 'rule names the unit' 1 "$(grep -c 'action.lookup("unit") == "devpanel.service"' "$rule")"
expect 'rule names the user' 1 "$(grep -c 'subject.user == "codepad"' "$rule")"
expect 'enable is not granted' 0 "$(grep -c 'manage-unit-files' "$rule")"
sc authorize-user-service codepad app@1.service > /dev/null
sc authorize-user-service web-dev devpanel.service > /dev/null
expect 'listing per user' 'Services codepad may manage: app@1.service devpanel.service' "$(sc authorize-user-service codepad)"
sc authorize-user-service codepad devpanel off > /dev/null
expect 'off removes only that rule' 'Services codepad may manage: app@1.service' "$(sc authorize-user-service codepad)"
expect 'other user kept' 'Services web-dev may manage: devpanel.service' "$(sc authorize-user-service web-dev)"

before="$(ls "$SC_POLKIT_RULES_DIR")"
expect 'unknown user refused' 'ERR No such user: nobody2' "$(sc authorize-user-service nobody2 devpanel)"
expect 'unknown unit refused' 'ERR No such service: nope.service' "$(sc authorize-user-service codepad nope)"
expect 'injection in unit refused' 'ERR Invalid service name: a");x("b.service' "$(sc authorize-user-service codepad 'a");x("b')"
expect 'bad user refused' 'ERR Invalid user name: Root"' "$(sc authorize-user-service 'Root"' devpanel)"
expect 'missing user' 'missing user' "$(sc authorize-user-service)"
expect 'nothing written by refusals' "$before" "$(ls "$SC_POLKIT_RULES_DIR")"
