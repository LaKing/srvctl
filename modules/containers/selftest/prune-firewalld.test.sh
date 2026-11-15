#!/bin/bash
#
# modules/containers/selftest/prune-firewalld.test.sh — a forwarded port is
# closed only when its service is named port-N, was opened by srvctl for a
# container, and no container forwards the port any more. firewall-cmd, getent
# and the datastore are stubbed. (Kept here: it needs this module's prunelib.)
# Run: bash modules/containers/selftest/prune-firewalld.test.sh

# shellcheck disable=SC2012,SC2034,SC2329
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

SC_PRUNE_SRV_DIR="$box/srv"
SC_FIREWALLD_SERVICE_DIR="$box/fw"
# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/prunelib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/firewalld/libs/prunelib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/srvctl/libs/retiredlib.sh"

## The zone lists every service of $ZONE; mutating calls are recorded.
ZONE=""
ZONE_RC=0
declare -a CALLS=()
firewall-cmd() {
    local arg
    for arg in "$@"
    do
        case $arg in
            --get-default-zone) echo public; return "$ZONE_RC" ;;
            --query-service=*) [[ " $ZONE " == *" ${arg#*=} "* ]] && echo yes || echo no; return 0 ;;
            --remove-service=*) CALLS+=("remove ${arg#*=}"); return 0 ;;
            --reload) CALLS+=("reload"); return 0 ;;
        esac
    done
}
getent() { [[ $2 == operator || $2 == root ]]; }
LIST_RC=0
list() { printf '%s\n' 'live.example	tcp/1200 udp/2001 tcp/2200' 'record-only.example	-'; return "$LIST_RC"; }

service() { ## name proto port note
    printf '%s\n' '<service>' "  <description>$1 $2 $3 ($4)</description>" "  <port protocol=\"$2\" port=\"$3\"/>" '</service>' > "$box/fw/$1.xml"
}
setup() {
    rm -rf "$box/fw" "$box/srv"
    mkdir -p "$box/fw" "$box/srv/live.example" "$box/srv/dir-only.example"
    service port-1200 tcp 1200 "srvctl added for live.example"
    service port-2001 udp 2001 "srvctl added for live.example"
    service port-1300 tcp 1300 "srvctl added for live.example"
    service port-1400 tcp 1400 "srvctl added for gone.example"
    service port-1500 udp 1500 "added by gone.example"
    service port-1600 tcp 1600 "added by srvctl"
    service port-1700 tcp 1700 "srvctl added for operator"
    service port-1800 tcp 1800 "srvctl added for root"
    service port-1900 tcp 1900 "srvctl added for dir-only.example"
    service port-2100 tcp 2100 "srvctl added for record-only.example"
    ## the port moved: opened for a container that is gone, mapped by another now
    service port-2200 tcp 2200 "srvctl added for gone.example"
    ## forwarded by the nspawn file of a container that has no record
    service port-2300 udp 2300 "srvctl added for dir-only.example"
    printf '%s\n' '[Network]' 'Port=udp:2300:53' 'Port=tcp:1900' > "$box/srv/dir-only.example/dir-only.example.nspawn"
    service custom tcp 1400 "srvctl added for gone.example"
    echo "<service/>" > "$box/fw/port-9999.xml"
    ZONE="port-1200 port-2001 port-1300 port-1400 port-1600 port-1700 port-1800 port-1900 port-2100 port-2200 port-2300 custom old-gui"
    ZONE_RC=0
    SC_PRUNE_CONTAINERS=" live.example record-only.example "
    CALLS=()
}
names() { (cd "$box/fw" && ls | sed 's/\.xml$//' | tr '\n' ' '); }

echo "dry run"
setup
SC_PRUNE_DRY_RUN=true prune_firewalld_ports
ok "keeps every service" "$(ls "$box/fw" | wc -l)" 14
ok "does not change the firewall" "${#CALLS[@]}" 0

echo "prune"
setup
prune_firewalld_ports
ok "closes only the ports that no record and no nspawn file forwards" "$(names)" "custom port-1200 port-1600 port-1700 port-1800 port-1900 port-2001 port-2200 port-2300 port-9999 "
ok "takes a service out of the zone only when the zone lists it, and reloads once" "${CALLS[*]}" "remove port-1300 remove port-1400 remove port-2100 reload"

echo "firewalld does not answer"
setup
ZONE_RC=1
prune_firewalld_ports
ok "keeps every definition" "$(ls "$box/fw" | wc -l)" 14
ok "does not reload" "${#CALLS[@]}" 0

echo "a failed datastore read"
setup
LIST_RC=112
prune_firewalld_ports
ok "closes nothing" "$(ls "$box/fw" | wc -l)" 14
LIST_RC=0
setup
SC_PRUNE_CONTAINERS=""
prune_firewalld_ports
ok "outside run_prune nothing is closed" "$(ls "$box/fw" | wc -l)" 14

echo "retired services"
setup
systemctl() { :; }
SC_RETIRED_UNITS=""
SC_RETIRED_PATHS=""
SC_RETIRED_EMPTY_DIRS=""
SC_RETIRED_FIREWALLD_SERVICES="old-gui absent"
service old-gui tcp 250 "added by srvctl"
SC_PRUNE_DRY_RUN=true prune_retired
ok "a dry run keeps the retired service" "$([[ -e $box/fw/old-gui.xml ]] && echo present)" present
ok "a dry run does not change the firewall" "${#CALLS[@]}" 0
prune_retired
ok "the retired service's definition is gone" "$([[ -e $box/fw/old-gui.xml ]] && echo present || echo gone)" gone
ok "it left the zone first, with one reload" "${CALLS[*]}" "remove old-gui reload"
CALLS=()
prune_retired
ok "a second run does nothing" "${#CALLS[@]}" 0

echo ""
echo "prune-firewalld.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
