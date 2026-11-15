#!/bin/bash
#
# modules/containers/selftest/prune-modules.test.sh — the prune functions of
# the other modules (static, opendkim, certificates, datastore, comount) all
# rely on container_is_gone of this module; each is run against the same four
# containers: live (record and directory), record-only, dir-only and gone.
# The firewalld one has its own file, prune-firewalld.test.sh.
# Run: bash modules/containers/selftest/prune-modules.test.sh

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
HOSTNAME=host.example
SC_MOUNTINFO="$box/mountinfo"
: > "$SC_MOUNTINFO"
# shellcheck source=/dev/null
source "$REPO/lablib.sh"
ntc() { :; }
declare -a ERRORS=()
err() { ERRORS+=("$*"); }

SC_PRUNE_SRV_DIR="$box/srv"
SC_COMOUNT_ROOT="$box/srv"
SC_COMOUNT_UNIT_DIR="$box/units"
SC_STATIC_DIR="$box/static"
SC_DATASTORE_DIR="$box/ds"
SC_DATASTORE_RW_DIR="$box/ds"
for lib in containers static opendkim certificates datastore comount
do
    # shellcheck source=/dev/null
    source "$REPO/modules/$lib/libs/prunelib.sh"
done

declare -a CALLS=()
systemctl() { CALLS+=("$*"); }
## the certificate named expired is past its end date, garbage is no certificate
openssl() {
    case "$*" in
        *garbage*) return 1 ;;
        *expired*-checkend*) return 1 ;;
        *) return 0 ;;
    esac
}
DOMAINS='live.example	["live.example","www.live.example","alias.example","www.alias.example"]
record-only.example	[]'
LIST_RC=0
list() { printf '%s\n' "$DOMAINS"; return "$LIST_RC"; }

ALL="live.example record-only.example dir-only.example gone.example"
setup() {
    local C
    rm -rf "$box/srv" "$box/units" "$box/static" "$box/ds"
    mkdir -p "$box/srv/live.example" "$box/srv/dir-only.example" "$box/units" "$box/ds/opendkim" "$box/ds/cert/wildcard" "$box/ds/cert/wildcard-retired" "$box/ds/.monolithic-backup"
    for C in $ALL
    do
        mkdir -p "$box/static/$C/html" "$box/ds/opendkim/$C"
        echo page > "$box/static/$C/html/index.html"
        echo key > "$box/ds/opendkim/$C/default.private"
        echo pem > "$box/ds/cert/$C.pem"
        printf '%s\n' '# srvctl comount' '[Mount]' "Where=$box/srv/$C/comount/data" > "$box/units/srv-$C-comount-data.mount"
    done
    echo table > "$box/ds/opendkim/KeyTable"
    SC_PRUNE_CONTAINERS=" live.example record-only.example "
    CALLS=()
    ERRORS=()
}
names() { (cd "$1" && ls | tr '\n' ' '); }

echo "static docroots"
setup
prune_static_docroots
ok "only the gone container's docroot is removed" "$(names "$box/static")" "dir-only.example live.example record-only.example "

echo "opendkim keys"
setup
prune_opendkim_keys
ok "only the gone container's key directory is removed, the tables stay" "$(names "$box/ds/opendkim")" "KeyTable dir-only.example live.example record-only.example "

echo "comount units"
setup
echo "Where=$box/srv/gone.example/comount/x" > "$box/units/srv-gone.example-comount-x.mount"
prune_comount_units
ok "the gone container's unit is removed, a file without the marker stays" "$(names "$box/units")" "srv-dir-only.example-comount-data.mount srv-gone.example-comount-x.mount srv-live.example-comount-data.mount srv-record-only.example-comount-data.mount "
ok "systemd reloads once" "${CALLS[*]}" "daemon-reload"
setup
SC_PRUNE_DRY_RUN=true prune_comount_units
ok "a dry run removes nothing" "$(ls "$box/units" | wc -l)" 4
ok "a dry run does not touch systemd" "${#CALLS[@]}" 0

echo "certificates"
setup
for name in alias.example www.alias.example old-alias.example host.example
do
    echo pem > "$box/ds/cert/$name.pem"
done
echo pem > "$box/ds/cert/wildcard/gone.example.pem"
echo pem > "$box/ds/cert/wildcard-retired/expired.example.pem"
echo pem > "$box/ds/cert/wildcard-retired/valid.example.pem"
echo junk > "$box/ds/cert/wildcard-retired/garbage.pem"
prune_certificates
ok "certificates of gone containers and removed aliases go; containers, their domains and the host stay" "$(cd "$box/ds/cert" && ls ./*.pem | tr '\n' ' ')" "./alias.example.pem ./dir-only.example.pem ./host.example.pem ./live.example.pem ./record-only.example.pem ./www.alias.example.pem "
ok "the wildcard directory is not touched" "$(names "$box/ds/cert/wildcard")" "gone.example.pem "
ok "a retired wildcard goes once expired; a valid one and an unreadable file stay" "$(names "$box/ds/cert/wildcard-retired")" "garbage.pem valid.example.pem "

setup
DOMAINS='live.example	-'
prune_certificates
ok "an underivable domain list removes nothing" "$(ls "$box/ds/cert"/*.pem | wc -l)" 4
ok "and says so" "${#ERRORS[@]}" 1
DOMAINS='live.example	["live.example"]'

setup
LIST_RC=112
prune_certificates
ok "a failed datastore read removes nothing" "$(ls "$box/ds/cert"/*.pem | wc -l)" 4
LIST_RC=0

echo "the last record deleted (run_prune over an empty datastore)"
## remove-ve of the final, domain-only record: list succeeds with no rows
run_hook() { prune_opendkim_keys; prune_static_docroots; }
setup
mkdir -p "$box/static/retired.example/html" "$box/ds/opendkim/retired.example"
echo key > "$box/ds/opendkim/retired.example/default.private"
DOMAINS=""
run_prune
ok "its preserved DKIM key goes" "$([[ -e $box/ds/opendkim/retired.example ]] && echo kept || echo gone)" gone
ok "its static docroot goes" "$([[ -e $box/static/retired.example ]] && echo kept || echo gone)" gone
ok "a directory in /srv still keeps its key" "$([[ -e $box/ds/opendkim/live.example ]] && echo kept || echo gone)" kept
setup
mkdir -p "$box/static/retired.example/html" "$box/ds/opendkim/retired.example"
LIST_RC=112
run_prune
ok "a failed datastore read prunes nothing" "$(find "$box/static" "$box/ds/opendkim" -maxdepth 1 -name '*.example' | wc -l)" 10
LIST_RC=0
DOMAINS='live.example	["live.example","www.live.example","alias.example","www.alias.example"]
record-only.example	[]'
unset -f run_hook

echo "outside run_prune"
setup
SC_PRUNE_CONTAINERS=""
prune_static_docroots
prune_opendkim_keys
prune_comount_units
prune_certificates
ok "nothing counts as gone without the records" "$(find "$box/static" "$box/ds/opendkim" "$box/ds/cert" "$box/units" -name '*gone.example*' | wc -l)" 4

echo "single-file datastore"
mono() { (cd "$box/ds" && ls ./*.json 2> /dev/null | tr '\n' ' '); }
seed() {
    local type
    setup
    for type in hosts users containers
    do
        echo "{\"$type\":1}" > "$box/ds/$type.json"
        cp "$box/ds/$type.json" "$box/ds/.monolithic-backup/"
    done
}
seed
prune_monolithic_datastore
ok "without the marker the files are the datastore and stay" "$(mono)" "./containers.json ./hosts.json ./users.json "
: > "$box/ds/.per-entity"
SC_PRUNE_DRY_RUN=true prune_monolithic_datastore
ok "a dry run removes nothing" "$(mono)" "./containers.json ./hosts.json ./users.json "
prune_monolithic_datastore
ok "with the marker the three files go" "$(mono)" ""
ok "the backup copies stay" "$(ls "$box/ds/.monolithic-backup" | wc -l)" 3
seed
: > "$box/ds/.per-entity"
echo changed >> "$box/ds/users.json"
prune_monolithic_datastore
ok "a file that differs from its backup keeps all three" "$(mono)" "./containers.json ./hosts.json ./users.json "
ok "and says so" "${#ERRORS[@]}" 1
seed
: > "$box/ds/.per-entity"
rm "$box/ds/.monolithic-backup/hosts.json"
prune_monolithic_datastore
ok "a file without a backup keeps all three" "$(mono)" "./containers.json ./hosts.json ./users.json "

echo ""
echo "prune-modules.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
