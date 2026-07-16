#!/bin/bash
# Child-side generation gate. An all-host regeneration controller passes the
# generation its plan was computed from (SC_EXPECTED_CLUSTERS_SHA256); a child
# whose freshly verified canonical generation differs must abort with 113
# before any hook or command runs. Exercises the REAL srvctl.sh init: works
# both on a configured cluster host (expected vs live sha) and on an
# unconfigured one (expected vs 'none').

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
pass=0
fail=0
ok() {
    if [[ $2 == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}

mismatch="$(printf 'a%.0s' {1..64})"
live_sha=""
if [[ -f /etc/srvctl/clusters.json ]]
then
    live_sha="$(sha256sum /etc/srvctl/clusters.json | cut -d' ' -f1)"
    [[ $live_sha == "$mismatch" ]] && mismatch="$(printf 'b%.0s' {1..64})"
fi

SC_EXPECTED_CLUSTERS_SHA256="$mismatch" bash "$REPO/srvctl.sh" version > /dev/null 2>&1
ok "mismatched plan generation aborts with 113" "$?" 113

SC_EXPECTED_CLUSTERS_SHA256="not-a-sha256" bash "$REPO/srvctl.sh" version > /dev/null 2>&1
ok "non-hex expectation is ignored" "$?" 0

bash "$REPO/srvctl.sh" version > /dev/null 2>&1
ok "absent expectation is unaffected" "$?" 0

if [[ -n $live_sha ]]
then
    SC_EXPECTED_CLUSTERS_SHA256="$live_sha" bash "$REPO/srvctl.sh" version > /dev/null 2>&1
    ok "matching plan generation proceeds" "$?" 0
fi

echo "expected-generation.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
