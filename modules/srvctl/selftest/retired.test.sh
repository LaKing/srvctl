#!/bin/bash
#
# modules/srvctl/selftest/retired.test.sh — the prune hook removes what
# removed modules left on a host, and nothing else. systemctl is stubbed.
# Run: bash modules/srvctl/selftest/retired.test.sh

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
# shellcheck source=/dev/null
source "$REPO/modules/srvctl/libs/retiredlib.sh"
ntc() { :; }
declare -a CALLS=()
systemctl() { CALLS+=("$*"); }

ok "the gui unit is on the shipped list" "$([[ " $SC_RETIRED_UNITS " == *" srvctl-gui.service "* ]] && echo yes)" yes

SC_RETIRED_UNIT_DIR="$box/units"
SC_RETIRED_UNITS="old-gui.service absent.service"
SC_RETIRED_PATHS="$box/etc/old-gui $box/var/commands.spec $box/var/absent"
SC_RETIRED_EMPTY_DIRS="$box/var/gluster/data $box/var/gluster $box/var/used"
mkdir -p "$box/units" "$box/etc/old-gui/cert" "$box/var/gluster/data" "$box/var/used" "$box/var/live"
touch "$box/units/old-gui.service" "$box/units/live.service" "$box/var/commands.spec" "$box/var/used/file" "$box/var/live/file"

SC_PRUNE_DRY_RUN=true prune_retired
ok "a dry run keeps everything" "$(find "$box/units" "$box/etc" "$box/var" | wc -l)" 14
ok "a dry run does not touch systemd" "${#CALLS[@]}" 0

prune_retired
ok "the retired unit is disabled and stopped before its file goes" "${CALLS[*]}" "disable --now old-gui.service reset-failed old-gui.service"
ok "the unit file is gone" "$(ls "$box/units")" "live.service"
ok "retired paths are gone with their content" "$(ls "$box/etc")" ""
ok "empty retired directories are gone, parent after child" "$([[ -e $box/var/gluster ]] && echo present || echo gone)" gone
ok "a retired directory with content stays" "$(ls "$box/var/used")" "file"
ok "nothing else is touched" "$(ls "$box/var/live")" "file"

CALLS=()
prune_retired
ok "a second run finds nothing to do" "${#CALLS[@]}" 0

echo ""
echo "retired.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
