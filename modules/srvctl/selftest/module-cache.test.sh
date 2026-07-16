#!/bin/bash
# Generation-keyed and atomic module cache tests.
# Test doubles and variables are consumed by sourced production functions.
# shellcheck disable=SC2034,SC2329

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0

ok() {
    if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else
        fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"
    fi
}

make_module() {
    mkdir -p "$1/testmodule"
    printf '%s\n' '#!/bin/bash' 'echo true' > "$1/testmodule/module-condition.sh"
}

run_success_case() (
    SRVCTL=1
    SC_HOME="$tmp/success/home"
    SC_MODULES="$tmp/success/modules/testmodule"
    SC_CANONICAL_CLUSTERS_SHA256="$(printf a%.0s {1..64})"
    SC_CLUSTERS_SHA256="$(printf f%.0s {1..64})"
    CMD=status
    mkdir -p "$SC_HOME"; make_module "$tmp/success/modules"
    # shellcheck source=/dev/null
    source "$REPO/commonlib.sh"
    msg() { :; }; ntc() { :; }; err() { :; }; debug() { :; }
    test_srvctl_modules || exit $?
    cache="$SC_HOME/.srvctl/modules.conf"
    grep -qxF "export SC_MODULES_CLUSTERS_SHA256=$SC_CANONICAL_CLUSTERS_SHA256" "$cache" || exit 20
    grep -qxF 'export SC_USE_TESTMODULE=true' "$cache" || exit 21
    [[ ${SC_USE_TESTMODULE:-} == true ]] || exit 22
)
ok "generation cache created and sourced" "$(run_success_case; echo $?)" 0

run_crash_window_case() (
    SRVCTL=1
    SC_HOME="$tmp/crash/home"
    SC_MODULES="$tmp/crash/modules/testmodule"
    SC_CLUSTERS_SHA256="$(printf b%.0s {1..64})"
    CMD=status
    mkdir -p "$SC_HOME/.srvctl"; make_module "$tmp/crash/modules"
    cache="$SC_HOME/.srvctl/modules.conf"
    printf '%s\n' \
        "export SC_MODULES_CLUSTERS_SHA256=$(printf a%.0s {1..64})" \
        'export SC_USE_TESTMODULE=false' > "$cache"
    before="$(<"$cache")"
    # shellcheck source=/dev/null
    source "$REPO/commonlib.sh"
    msg() { :; }; ntc() { :; }; err() { :; }; debug() { :; }
    mv() { return 55; }
    if test_srvctl_modules; then rc=0; else rc=$?; fi
    [[ $rc == 113 ]] || exit 30
    [[ $(<"$cache") == "$before" ]] || exit 31
)
ok "failed atomic rename preserves old complete cache" "$(run_crash_window_case; echo $?)" 0

run_bad_hash_case() (
    SRVCTL=1 SC_HOME="$tmp/bad/home" SC_MODULES="" SC_CLUSTERS_SHA256=bad CMD=status
    mkdir -p "$SC_HOME"
    # shellcheck source=/dev/null
    source "$REPO/commonlib.sh"
    msg() { :; }; ntc() { :; }; err() { :; }; debug() { :; }
    if test_srvctl_modules; then exit 40; else [[ $? == 113 ]]; fi
)
ok "invalid generation fails closed" "$(run_bad_hash_case; echo $?)" 0

init_pair="$(awk '/^[[:space:]]*test_srvctl_modules[[:space:]]*$/ { getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }' "$REPO/init.sh")"
ok "init propagates module cache failure" "$init_pair" 'exif "MODULE-CONFIG"'

echo "module-cache.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
