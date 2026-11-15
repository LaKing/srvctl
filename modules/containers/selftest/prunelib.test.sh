#!/bin/bash
#
# modules/containers/selftest/prunelib.test.sh — the artifacts of a container
# are removed only when it has neither a record nor a directory. The
# datastore and systemctl are stubbed.
# Run: bash modules/containers/selftest/prunelib.test.sh

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

box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
SC_LOG="$box/log"
NOW=now
SC_USER=tester
SC_MOUNTINFO="$box/mountinfo"
: > "$SC_MOUNTINFO"
# shellcheck source=/dev/null
source "$REPO/lablib.sh"
ntc() { :; }
err() { :; }

SC_PRUNE_UNIT_DIR="$box/units"
SC_PRUNE_SHARE_DIR="$box/share"
SC_PRUNE_SRV_DIR="$box/srv"
# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/prunelib.sh"

RECORDS=$'live.example\nrecord-only.example\n'
LIST_RC=0
list() { printf '%s' "$RECORDS"; return "$LIST_RC"; }
## run_prune reads the records, then runs the hooks; this module's hook is one call
run_hook() { prune_container_leftovers; }
FAILED="srvctl-nspawn@gone.example.service loaded failed failed x"$'\n'"srvctl-nspawn@live.example.service loaded failed failed x"$'\n'
declare -a CALLS=()
systemctl() {
    if [[ $1 == list-units ]]
    then
        printf '%s' "$FAILED"
    else
        CALLS+=("$*")
    fi
}

setup() {
    rm -rf "$box/units" "$box/share" "$box/srv"
    mkdir -p "$box/units/machines.target.wants" "$box/srv/live.example/rootfs" "$box/srv/dir-only.example/rootfs"
    local C
    for C in live.example record-only.example dir-only.example gone.example
    do
        ln -s /dev/null "$box/units/machines.target.wants/srvctl-nspawn@$C.service"
        mkdir -p "$box/units/srvctl-nspawn@$C.service.d" "$box/share/$C/users"
        echo limits > "$box/units/srvctl-nspawn@$C.service.d/50-srvctl-limits.conf"
        echo hash > "$box/share/$C/users/key"
    done
    touch "$box/units/other.service"
    CALLS=()
}
left() { find "$box/units" "$box/share" -name "*$1*" | wc -l; }

echo "dry run"
setup
SC_PRUNE_DRY_RUN=true run_prune
ok "keeps the gone container's artifacts" "$(left gone.example)" 3
ok "does not touch systemd" "${#CALLS[@]}" 0

echo "prune"
setup
run_prune; ok "rc" $? 0
ok "a container with neither record nor directory loses everything" "$(left gone.example)" 0
ok "a running container keeps everything" "$(left live.example)" 3
ok "a record without a directory keeps everything" "$(left record-only.example)" 3
ok "a directory without a record keeps everything" "$(left dir-only.example)" 3
ok "unrelated units stay" "$([[ -e $box/units/other.service ]] && echo present)" present
ok "systemd reloads once and forgets the removed container's failed unit only" "${CALLS[*]}" "daemon-reload reset-failed srvctl-nspawn@gone.example.service"

echo "a failed datastore read"
setup
RECORDS=""
LIST_RC=112
run_prune; ok "rc" $? 0
ok "prunes nothing, although no record is visible" "$(left example)" 12
ok "does not touch systemd" "${#CALLS[@]}" 0
LIST_RC=0

echo "a mounted share"
setup
RECORDS=$'live.example\nrecord-only.example\n'
echo "36 25 0:32 / $box/share/gone.example/users rw - fuse.bindfs x rw" > "$SC_MOUNTINFO"
run_prune
ok "a share with a mount in it is kept" "$(cat "$box/share/gone.example/users/key")" hash
ok "the rest of the container's artifacts still go" "$(find "$box/units" -name '*gone.example*' | wc -l)" 0

echo "outside run_prune"
setup
prune_container_leftovers
ok "nothing counts as gone without the records" "$(left example)" 12

echo ""
echo "prunelib.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
