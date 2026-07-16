#!/bin/bash
# Regression coverage for immediate, ordered DNS override publication.

# Test doubles and their variables are consumed by the command sourced below.
# shellcheck disable=SC2034,SC2329
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
COMMAND="$REPO/modules/named/commands/override-in-address.sh"

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

probe() {
    local value="${1:-38.242.131.65}"
    local put_rc="${2:-0}"
    local publish_rc="${3:-0}"
    local markfile
    markfile="$(mktemp)"

    (
        mark() { printf '%s|' "$*" >> "$markfile"; }
        hs_only() { mark hs_only; }
        argument() { mark "argument:$*"; }
        get() {
            [[ $3 == user ]] && echo alice || echo reseller
        }
        exif() {
            local rc=$?
            [[ $rc -eq 0 ]] || exit "$rc"
        }
        err() { mark "err:$*"; }
        msg() { :; }
        owner_only() { mark "owner_only:$*"; }
        put() {
            mark "put:$*"
            return "$put_rc"
        }
        regenerate_all_hosts() {
            mark regenerate_all_hosts
            return "$publish_rc"
        }
        SRVCTL=1
        ARG=mindtalk.hu
        OPA="$value"

        # shellcheck source=/dev/null
        source "$COMMAND"
    )
    RC=$?
    MARKS="$(<"$markfile")"
    rm -f "$markfile"
}

probe
ok "successful command returns zero" "$RC" "0"
ok "override is persisted before cluster publication" "$MARKS" \
    "hs_only|argument:container|owner_only:container mindtalk.hu|put:container mindtalk.hu override_in_a_ip 38.242.131.65|regenerate_all_hosts|"

probe 38.242.131.65 0 23
ok "publication failure is returned" "$RC" "23"

probe none
ok "none sentinel is accepted" "$RC" "0"
ok "none sentinel is persisted" "$MARKS" \
    "hs_only|argument:container|owner_only:container mindtalk.hu|put:container mindtalk.hu override_in_a_ip none|regenerate_all_hosts|"

probe 38.242.131.65 17
ok "put failure is returned exactly" "$RC" "17"
ok "put failure never regenerates" "$MARKS" \
    "hs_only|argument:container|owner_only:container mindtalk.hu|put:container mindtalk.hu override_in_a_ip 38.242.131.65|"

probe 256.2.3.4
ok "invalid IPv4 returns invalid-input status" "$RC" "22"
ok "invalid IPv4 never writes or regenerates" "$MARKS" \
    "hs_only|argument:container|err:Invalid IN A override: 256.2.3.4 (expected none or an IPv4 address)|"

echo "override-in-address.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
