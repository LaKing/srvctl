#!/bin/bash
#
# modules/containers/selftest/removelib.test.sh — a container tree is deleted
# only when nothing is mounted below it. systemctl and umount are stubbed and
# the mount table is a file.
# Run: bash modules/containers/selftest/removelib.test.sh

# Stubs are consumed by the sourced library.
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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
SC_MOUNTINFO="$tmp/mountinfo"
SC_REMOVE_RETRY_SLEEP=0
declare -a CALLS=()
UMOUNT_WORKS=true

msg() { :; }
ntc() { :; }
err() { :; }
run() { "$@"; }
systemctl() { CALLS+=("systemctl $*"); }
## A successful umount takes the line out of the mount table.
umount() {
    CALLS+=("umount $1")
    $UMOUNT_WORKS || return 32
    grep -v " $1 " "$SC_MOUNTINFO" > "$SC_MOUNTINFO.new"
    mv "$SC_MOUNTINFO.new" "$SC_MOUNTINFO"
}

# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/removelib.sh"

mountline() { echo "36 25 0:32 / $1 rw,relatime shared:1 - xfs /dev/md0 rw"; }
tree() {
    mkdir -p "$tmp/srv/$1/rootfs/etc" "$tmp/srv/$1/comount/uploads" "$tmp/srv/other.example/rootfs"
    echo shared > "$tmp/srv/$1/comount/uploads/data"
}

echo "nothing mounted"
tree a.example
mountline "$tmp/srv/other.example/comount/uploads" > "$SC_MOUNTINFO"
CALLS=()
remove_container_tree a.example "$tmp/srv/a.example"; ok "rc" $? 0
ok "the tree is gone" "$([[ -e $tmp/srv/a.example ]] && echo present || echo gone)" gone
ok "the unit is stopped first, a neighbour's mount is not touched" "${CALLS[*]}" "systemctl stop srvctl-nspawn@a.example.service"
ok "a neighbour is not touched" "$([[ -d $tmp/srv/other.example/rootfs ]] && echo present)" present

echo "a mount that unmounts"
tree b.example
{ mountline "$tmp/srv/b.example/comount/uploads"; mountline "$tmp/srv/b.example/comount"; } > "$SC_MOUNTINFO"
CALLS=()
remove_container_tree b.example "$tmp/srv/b.example"; ok "rc" $? 0
ok "unmounts deepest first" "${CALLS[*]:1}" "umount $tmp/srv/b.example/comount/uploads umount $tmp/srv/b.example/comount"
ok "the tree is gone" "$([[ -e $tmp/srv/b.example ]] && echo present || echo gone)" gone

echo "a mount that stays"
tree c.example
mountline "$tmp/srv/c.example/comount/uploads" > "$SC_MOUNTINFO"
UMOUNT_WORKS=false
remove_container_tree c.example "$tmp/srv/c.example"; ok "rc" $? 16
ok "nothing is deleted, shared data included" "$(cat "$tmp/srv/c.example/comount/uploads/data")" shared
ok "the rootfs is kept too" "$([[ -d $tmp/srv/c.example/rootfs/etc ]] && echo present)" present
UMOUNT_WORKS=true

echo "refusals"
: > "$SC_MOUNTINFO"
remove_container_tree "" "$tmp/srv/"; ok "empty name" $? 22
remove_container_tree "../srv" "$tmp/srv/../srv"; ok "path in the name" $? 22
remove_container_tree a.example "$tmp/srv"; ok "directory that is not the container's" $? 22
ok "the parent survives all of them" "$([[ -d $tmp/srv/other.example ]] && echo present)" present
remove_container_tree gone.example "$tmp/srv/gone.example"; ok "a missing tree is not an error" $? 0

echo ""
echo "removelib.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
