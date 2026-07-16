#!/bin/bash
# Verify fresh-snapshot policy and lock invocation without running Node.

# Test doubles are invoked indirectly by the sourced production function.
# shellcheck disable=SC2329
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
# shellcheck disable=SC2034 # consumed by the sourced production function
SC_INSTALL_DIR="$REPO"

# shellcheck source=/dev/null
source "$REPO/modules/named/libs/bashlib.sh"

pass=0
fail=0
POLICIES=""
LOCK_ARGS=""
EXIF_STATUS=0
FLOCK_RC=0

flock() {
    POLICIES+="${SC_NAMED_REQUIRE_FRESH:-unset}|"
    LOCK_ARGS="$*"
    return "$FLOCK_RC"
}
exif() {
    EXIF_STATUS=$?
}
ok() {
    if [[ $2 == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}

# shellcheck disable=SC2034 # consumed by the sourced production function
ARG=""
namedcfg
ok "manual regeneration requires fresh peers" "$POLICIES" "true|"
ok "manual regeneration forces replica convergence" "$NAMED_FORCE_RETRANSFER" "true"
ok "generator is serialized" "$LOCK_ARGS" \
    "--wait 60 /run/srvctl-named-regenerate.lock /bin/node $REPO/modules/named/named.js"

# shellcheck disable=SC2034 # consumed by the sourced production function
ARG="#cron.hourly"
namedcfg
ok "hourly run may use bounded cache" "$POLICIES" "true|false|"
ok "hourly run uses lightweight replica refresh" "$NAMED_FORCE_RETRANSFER" "false"

FLOCK_RC=23
# shellcheck disable=SC2034 # consumed by the sourced production function
ARG=""
namedcfg
ok "lock/generator failure reaches exif" "$EXIF_STATUS" "23"

echo "bashlib.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
