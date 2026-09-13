#!/bin/bash
# Isolated module tests using srvctl get/put/run mocks and temporary host paths.
set -euo pipefail
SC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SRVCTL='test'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=modules/comount/libs/comountlib.sh
source "$SC_INSTALL_DIR/modules/comount/libs/comountlib.sh"

declare -A records=() offsets=() active=() mounted=()
fail_get=0 fail_start=0 count=0
msg() { echo "$*" >> "$tmp/messages"; }
err() { echo "$*" >> "$tmp/errors"; }
debug() { :; }
run() { printf '%s\n' "$*" >> "$tmp/calls"; "$@"; }
get() {
    if ((fail_get)); then return "$fail_get"; fi
    if [[ $1 == cluster ]]; then echo 'src.test a.test b.test remote.test'; return; fi
    case $3 in
        host) if [[ $2 == remote.test ]]; then echo elsewhere; else echo "$HOSTNAME"; fi ;;
        uid) echo "${offsets[$2]}" ;;
        comount-*) [[ ${records[$2:$3]+yes} ]] || return 100; echo "${records[$2:$3]}" ;;
        *) return 110 ;;
    esac
}
put() {
    printf '%s\n' "put $*" >> "$tmp/calls"
    if (($# == 4)); then records[$2:$3]=$4; else unset "records[$2:$3]"; fi
}
out() {
    if ((fail_get)); then return "$fail_get"; fi
    local key separator=''
    printf '{'
    for key in "${!records[@]}"
    do
        [[ $key == "$2:"* ]] || continue
        printf '%s"%s":"%s"' "$separator" "${key#"$2:"}" "${records[$key]}"
        separator=,
    done
    printf '}\n'
}
stat() {
    if [[ ${!#} == "$SC_COMOUNT_ROOT"/*/rootfs ]]; then
        local c=${!#}; c=${c#"$SC_COMOUNT_ROOT/"}; c=${c%/rootfs}
        echo "${offsets[$c]}:${offsets[$c]}"
    elif [[ ${!#} == "$SC_COMOUNT_STORAGE/as-root/"* && $2 == '%u:%g' ]]; then
        echo '0:0'
    elif [[ ${!#} == "$SC_COMOUNT_STORAGE/as-codepad/"* && $2 == '%u:%g' ]]; then
        echo '804:804'
    else command stat "$@"; fi
}
findmnt() { echo /; }
mountpoint() { [[ ${mounted[${!#}]:-false} == true ]]; }
chown() { :; }
systemctl() {
    local unit=${!#} c
    case $1 in
        is-active) [[ ${active[$unit]:-false} == true ]] ;;
        stop)
            active[$unit]=false
            if [[ $unit == *.mount ]]; then mounted[$SC_COMOUNT_MOUNT]=false; fi ;;
        start)
            ((fail_start == 0)) || return "$fail_start"
            active[$unit]=true
            if [[ $unit == srvctl-nspawn@* ]]; then
                c=${unit#srvctl-nspawn@}; c=${c%.service}
                [[ ! -f $SC_COMOUNT_ROOT/$c/binds/comount-project.binds ]] || mounted[$SC_COMOUNT_ROOT/$c/comount/project]=true
            fi ;;
        daemon-reload|status) return 0 ;;
        *) return 1 ;;
    esac
}
systemd-run() { printf '%s\n' "${8}" >> "$tmp/verify-calls"; printf '%s\n' "$@" > "$tmp/verify-argv"; }

new_case() {
    count=$((count + 1))
    SC_COMOUNT_ROOT="$tmp/case$count/srv"
    SC_COMOUNT_STORAGE="$tmp/case$count/storage"
    SC_COMOUNT_UNIT_DIR="$tmp/case$count/units"
    records=(); active=(); mounted=(); offsets=()
    offsets[src.test]=7798784; offsets[a.test]=7864320; offsets[b.test]=7929856
    fail_get=0; fail_start=0
    local c
    for c in src.test a.test b.test
    do
        mkdir -p "$SC_COMOUNT_ROOT/$c/rootfs/etc"
        echo 'codepad:x:804:804::/var/codepad:/bin/bash' > "$SC_COMOUNT_ROOT/$c/rootfs/etc/passwd"
    done
    source_path="$SC_COMOUNT_STORAGE/as-codepad/srv/project"
    mkdir -p "$source_path"
    : > "$tmp/calls"
    : > "$tmp/verify-calls"
}
expect() {
    [[ $2 == "$3" ]] || { echo "FAIL $1: expected '$2', got '$3'"; exit 1; }
    echo "PASS $1"
}
failure() {
    local rc
    if "$@"; then echo "FAIL: unexpectedly succeeded: $*"; exit 1; else rc=$?; fi
    expect "$* exit" "${expected_rc:-22}" "$rc"
}

new_case
comount_parameters a.test "$source_path"
expect 'source IDs' '804:804' "$SC_COMOUNT_SOURCE_UID:$SC_COMOUNT_SOURCE_GID"
expect 'target IDs' '7865124:7865124' "$SC_COMOUNT_UID:$SC_COMOUNT_GID"
expect 'destination' /srv/project "$SC_COMOUNT_DEST"
expect 'mapping direction' 'Options=bind,rw,X-mount.idmap=u:804:7865124:1 g:804:7865124:1 u:0:7864320:1 g:0:7864320:1' "$(comount_mount_config | tail -1)"
expect 'mount follows container stop' 'PartOf=srvctl-nspawn@a.test.service' "$(comount_mount_config | grep '^PartOf=')"
expect 'unused mount is stopped' 'StopWhenUnneeded=yes' "$(comount_mount_config | grep '^StopWhenUnneeded=')"
sed -i 's/:804:804:/:804:805:/' "$SC_COMOUNT_ROOT/a.test/rootfs/etc/passwd"
comount_parameters a.test "$source_path"
expect 'distinct GID' 7865125 "$SC_COMOUNT_GID"

new_case
add_comount_to_containers codepad /srv/project a.test b.test
expect 'datastore source a' "$source_path" "${records[a.test:comount-project]}"
expect 'datastore source b' "$source_path" "${records[b.test:comount-project]}"
expect 'stopped containers remain stopped' 0 "$(grep -c 'systemctl start' "$tmp/calls" || true)"
expect 'two generated binds' 2 "$(find "$SC_COMOUNT_ROOT" -name 'comount-*.binds' | wc -l)"
: > "$tmp/calls"
regenerate_comounts
expect 'unchanged regenerate has no effects' '' "$(cat "$tmp/calls")"
unset 'records[a.test:comount-project]'
regenerate_comounts
expect 'cleared setting removes generated bind' no "$([[ -e $SC_COMOUNT_ROOT/a.test/binds/comount-project.binds ]] && echo yes || echo no)"
expect 'regenerate cleanup does not mutate datastore' 0 "$(grep -c '^put ' "$tmp/calls" || true)"

# Different container codepad IDs must still use the same stable backing IDs.
new_case
sed -i 's/:804:804:/:900:901:/' "$SC_COMOUNT_ROOT/b.test/rootfs/etc/passwd"
add_comount_to_containers codepad /srv/project a.test b.test
comount_parameters b.test "$source_path"
expect 'stable backing UID without host account lookup' 804 "$SC_COMOUNT_SOURCE_UID"
expect 'different target UID and GID' '7930756:7930757' "$SC_COMOUNT_UID:$SC_COMOUNT_GID"
: > "$tmp/calls"
regenerate_comounts
expect 'mixed target IDs regenerate unchanged' '' "$(cat "$tmp/calls")"

new_case
active[srvctl-nspawn@a.test.service]=true
add_comount_to_containers codepad /srv/project a.test
expect 'running target restarted' true "${active[srvctl-nspawn@a.test.service]}"
expect 'one stop on first apply' 1 "$(grep -c 'systemctl stop srvctl-nspawn@a.test.service' "$tmp/calls")"
: > "$tmp/calls"
# Simulate the previously generated codepad-only mapping on a live share.
sed -i 's/ u:0:[0-9]*:1 g:0:[0-9]*:1$//' "$SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT"
regenerate_comounts
expect 'old mapping restarts container once' 1 "$(grep -c 'systemctl stop srvctl-nspawn@a.test.service' "$tmp/calls")"
expect 'old mapping is unmounted' 1 "$(grep -c 'systemctl stop .*\.mount' "$tmp/calls")"
expect 'regeneration preserves ownership' 0 "$(grep -c chown "$tmp/calls" || true)"
: > "$tmp/calls"
regenerate_comounts
expect 'hourly regenerate does not restart unchanged target' '' "$(cat "$tmp/calls")"
sed -i 's/:804:804:/:804:805:/' "$SC_COMOUNT_ROOT/a.test/rootfs/etc/passwd"
regenerate_comounts
expect 'changed ID remounts' 1 "$(grep -c 'systemctl stop .*\.mount' "$tmp/calls")"
test_comount a.test project
expect 'codepad share tests both accounts' 2 "$(wc -l < "$tmp/verify-calls")"
expect 'codepad test included' 1 "$(grep -c '^codepad$' "$tmp/verify-calls")"
expect 'root test included' 1 "$(grep -c '^root$' "$tmp/verify-calls")"
expect 'test uses runuser' 1 "$(grep -c '^/usr/sbin/runuser$' "$tmp/verify-argv")"
expect 'test avoids uid/pipe failure' 0 "$(grep -c '^--uid' "$tmp/verify-argv" || true)"
remove_comount a.test project
expect 'remove clears setting' '' "${records[a.test:comount-project]:-}"
expect 'remove preserves source' yes "$([[ -d $source_path ]] && echo yes)"
expect 'remove restarts previously running target' true "${active[srvctl-nspawn@a.test.service]}"
expect 'remove deletes module config' 0 "$(find "$SC_COMOUNT_UNIT_DIR" -type f | wc -l)"

new_case
touch "$SC_COMOUNT_ROOT/b.test/local.nspawn"
failure add_comount_to_containers codepad /srv/project a.test b.test
expect 'invalid second target blocks all writes' '' "$(cat "$tmp/calls")"

new_case
mkdir -p "$SC_COMOUNT_ROOT/a.test/rootfs/srv/project"
echo keep > "$SC_COMOUNT_ROOT/a.test/rootfs/srv/project/keep"
failure add_comount_to_containers codepad /srv/project a.test
expect 'nonempty destination retained' keep "$(cat "$SC_COMOUNT_ROOT/a.test/rootfs/srv/project/keep")"

new_case
mkdir -p "$SC_COMOUNT_ROOT/a.test/binds"
printf '  BindReadOnly = /other:/srv/project/' > "$SC_COMOUNT_ROOT/a.test/binds/manual.binds"
failure add_comount_to_containers codepad /srv/project a.test
expect 'conflicting manual bind retained' yes "$([[ -f $SC_COMOUNT_ROOT/a.test/binds/manual.binds ]] && echo yes)"

new_case
fail_get=112
expected_rc=112 failure add_comount_to_containers codepad /srv/project a.test
expect 'datastore error blocks writes' '' "$(cat "$tmp/calls")"

new_case
records[a.test:comount-project]="$source_path"
fail_get=112
expected_rc=112 failure regenerate_comounts
expect 'regenerate does not treat datastore failures as deletion' "$source_path" "${records[a.test:comount-project]}"

new_case
active[srvctl-nspawn@a.test.service]=true
fail_start=77
expected_rc=77 failure add_comount_to_containers codepad /srv/project a.test
expect 'failed apply retains datastore intent' "$source_path" "${records[a.test:comount-project]}"

# Full container paths are rooted under the selected account's storage.
new_case
host_source="$SC_COMOUNT_STORAGE/as-codepad/srv/mycomount"
cache_source="$SC_COMOUNT_STORAGE/as-root/opt/cache"
add_comount_to_containers codepad /srv/mycomount a.test b.test
expect 'managed storage created' yes "$([[ -d $host_source ]] && echo yes)"
expect 'no source under host srv' no "$([[ -e $SC_COMOUNT_ROOT/mycomount ]] && echo yes || echo no)"
expect 'host source registered by name' "$host_source" "${records[a.test:comount-mycomount]}"
expect 'simple container path' "Bind=$SC_COMOUNT_ROOT/a.test/comount/mycomount:/srv/mycomount" "$(tail -1 "$SC_COMOUNT_ROOT/a.test/binds/comount-mycomount.binds")"
add_comount_to_containers root /opt/cache a.test b.test
expect 'root storage created' yes "$([[ -d $cache_source ]] && echo yes)"
comount_parameters a.test "$cache_source"
expect 'root UID mapping' 'Options=bind,rw,X-mount.idmap=u:0:7864320:1 g:0:7864320:1' "$(comount_mount_config | tail -1)"
expect 'full nested path retained' /opt/cache "$SC_COMOUNT_DEST"
comount_parameters b.test "$cache_source"
expect 'second container root mapping' 7929856 "$SC_COMOUNT_UID"
test_comount a.test cache
expect 'root test account' root "$(sed -n '/^-u$/{n;p;}' "$tmp/verify-argv")"
expect 'multiple named comounts' $'cache\nmycomount' "$(comount_names a.test)"
remove_comount a.test mycomount
expect 'removal keeps another share' "$cache_source" "${records[a.test:comount-cache]}"
expect 'removal keeps other memberships' "$host_source" "${records[b.test:comount-mycomount]}"
expect 'other bind remains' yes "$([[ -f $SC_COMOUNT_ROOT/a.test/binds/comount-cache.binds ]] && echo yes)"
: > "$tmp/calls"
failure add_comount_to_containers codepad /other/mycomount a.test
failure add_comount_to_containers root /srv/mycomount a.test
failure add_comount_to_containers codepad /srv/mycomount/child a.test
expect 'name, account and overlapping-source conflicts cause no writes' '' "$(cat "$tmp/calls")"

new_case
rm "$SC_COMOUNT_ROOT/a.test/rootfs/etc/passwd"
add_comount_to_containers root /srv/rootshare a.test
expect 'root does not require codepad account' "$SC_COMOUNT_STORAGE/as-root/srv/rootshare" "${records[a.test:comount-rootshare]}"
: > "$tmp/calls"
regenerate_comounts
expect 'root regeneration is unchanged' '' "$(cat "$tmp/calls")"

new_case
for bad in relative / /srv/../etc /srv/./project /srv//project
 do failure add_comount_to_containers codepad "$bad" a.test; done
expect 'invalid paths do not mutate' '' "$(cat "$tmp/calls")"
mkdir -p "$SC_COMOUNT_STORAGE/as-root"
ln -s "$tmp" "$SC_COMOUNT_STORAGE/as-root/srv"
failure add_comount_to_containers root /srv/escape a.test
expect 'storage symlink rejected before writes' '' "$(cat "$tmp/calls")"

new_case
legacy="$SC_COMOUNT_ROOT/legacy"
mkdir -p "$legacy"
records[a.test:comount-legacy]="$legacy"
failure regenerate_comounts
expect 'legacy source is not moved or chowned' '' "$(cat "$tmp/calls")"

new_case
add_comount_to_containers codepad /srv/assets.conf a.test
unset 'records[a.test:comount-assets.conf]'
rmdir "$SC_COMOUNT_ROOT/a.test/comount/assets.conf"
expect 'identifier extension retained during orphan cleanup' assets.conf "$(comount_known_names a.test)"
regenerate_comounts
expect 'orphan bind removed by its exact name' no "$([[ -e $SC_COMOUNT_ROOT/a.test/binds/comount-assets.conf.binds ]] && echo yes || echo no)"

# Command wrappers use the standard auth and argument guards before work.
new_case
root_only() { :; }
hs_only() { :; }
argument() { [[ -n $ARG ]]; }
exif() { local rc=$?; ((rc == 0)) || exit "$rc"; }
ARG=/srv/project
SC_ARGV=(add-codepad-comount-to-containers "$ARG" a.test)
# shellcheck source=modules/comount/commands/add-codepad-comount-to-containers.sh
source "$SC_INSTALL_DIR/modules/comount/commands/add-codepad-comount-to-containers.sh"
expect 'sourced command records configuration' "$source_path" "${records[a.test:comount-project]}"
ARG=/srv/rootshare
SC_ARGV=(add-root-comount-to-containers "$ARG" b.test)
# shellcheck source=modules/comount/commands/add-root-comount-to-containers.sh
source "$SC_INSTALL_DIR/modules/comount/commands/add-root-comount-to-containers.sh"
expect 'root command records configuration' "$SC_COMOUNT_STORAGE/as-root/srv/rootshare" "${records[b.test:comount-rootshare]}"
if (
    root_only() { exit 44; }
    # shellcheck source=modules/comount/commands/remove-comount.sh
    source "$SC_INSTALL_DIR/modules/comount/commands/remove-comount.sh"
); then echo 'FAIL unauthorized command'; exit 1; else expect 'auth guard' 44 "$?"; fi

echo 'All comount tests passed.'
