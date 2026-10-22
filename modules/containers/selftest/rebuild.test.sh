#!/bin/bash
# libs/rebuildlib.sh phase machine against a fake /srv and base image, with systemctl,
# machinectl, ssh and curl stubbed: order, resume, refusals, rollback, discard-old.
# The in-container scripts (lib/rebuild-ve-*.sh) need real containers; not covered here.
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

SC_REBUILD_SRV="$tmp/srv" SC_ROOTFS_DIR="$tmp/rootfs" SC_INSTALL_DIR="$REPO" NOW=now
C=wp.example d="$tmp/srv/wp.example" calls="$tmp/calls"

msg() { echo "$*"; }
ntc() { echo "$*"; }
err() { echo "ERR $*"; }
run() { "$@"; }
sleep() { :; }
chgrp() { :; } ## host keys: needs root
machinectl() { case $1 in show) [[ -f $tmp/running ]] ;; *) rm -f "$tmp/running" ;; esac; }
systemctl() { case $1 in start) touch "$tmp/running" ;; stop) rm -f "$tmp/running" ;; esac; }
init_ve_rootfs() { echo "init $1" >> "$calls"; }
create_nspawn_container_config() { echo "config $1" >> "$calls"; }
curl() {
    local out
    while (($#)); do [[ $1 == -o ]] && out="$2"; shift; done
    cat "$tmp/page" > "$out"
    cat "$tmp/code" 2> /dev/null || echo 200
}
# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/rebuildlib.sh"

## in-container halves: the backup leaves /srv/backup in the old tree; a restore may be told to fail
rebuild_ssh() {
    [[ -f $tmp/running ]] || return 255
    if [[ ${2:-} == bash ]]; then
        local script
        script="$(cat)"
        if [[ $script == *BACKUP-ERROR* ]]; then mkdir -p "$d/rootfs/srv/backup/files" && echo kind=wordpress > "$d/rootfs/srv/backup/manifest"; echo backup >> "$calls"; fi
        [[ $script == *RESTORE-ERROR* && -f $tmp/restore-fails ]] && return 1
        return 0
    fi
    [[ $2 != *is-enabled* ]] ## services all fine: the "enabled but not active" probe finds nothing
}


mkdir -p "$tmp/rootfs/fedora/usr/lib" "$tmp/rootfs/fedora/etc/ssh" "$tmp/rootfs/fedora/srv"
echo VERSION_ID=44 > "$tmp/rootfs/fedora/usr/lib/os-release"
touch "$tmp/rootfs/fedora/new-marker"
newold() {
    rm -rf "$d" && mkdir -p "$d/rootfs/etc/ssh" "$d/rootfs/usr/lib"
    echo 'PRETTY_NAME="Fedora 27"' > "$d/rootfs/usr/lib/os-release"
    touch "$d/rootfs/old-marker" "$d/rootfs/etc/ssh/ssh_host_ed25519_key"
}
echo '<html><title>My Site</title>' > "$tmp/page"
state() { tr '\n' ' ' 2> /dev/null < "$d/rebuild/state"; }

## unsupported content is refused before anything changes
newold && mkdir -p "$d/rootfs/var/codepad"
rebuild_ve "$C" > /dev/null
ok "unsupported refused" "$?" 1
ok "nothing recorded" "$(state)" ""
ok "not started" "$([[ -f $tmp/running ]] && echo yes)" ""

## an enabled unit defined outside the packages and outside /srv/<dir> or /home is refused too
newold && mkdir -p "$d/rootfs/etc/systemd/system/multi-user.target.wants"
ln -s /opt/app/app.service "$d/rootfs/etc/systemd/system/multi-user.target.wants/app.service"
ln -s /usr/lib/systemd/system/httpd.service "$d/rootfs/etc/systemd/system/multi-user.target.wants/httpd.service"
ok "local unit refused" "$(rebuild_ve "$C" | grep -c 'app.service (local unit)')" 1
rm "$d/rootfs/etc/systemd/system/multi-user.target.wants/app.service"
## one under /srv/<dir> (a Node app) is carried by the backup, so it passes
ln -s /srv/app/bash/app.service "$d/rootfs/etc/systemd/system/multi-user.target.wants/app.service"
ok "app unit under /srv passes preflight" "$(rebuild_ve_snapshot "$C" 2>&1 | grep -c 'rebuild-ve does not restore')" 0
rm -f "$tmp/running" "$d/rebuild/was-running" "$d/rootfs/etc/systemd/system/multi-user.target.wants/app.service"
ok "packaged unit alone passes preflight" "$(rebuild_ve_snapshot "$C" 2>&1 | grep -c 'rebuild-ve does not restore')" 0
rm -f "$tmp/running" "$d/rebuild/was-running"

## a restore failure stops there; the rerun continues at restore only
newold && touch "$tmp/restore-fails"
rebuild_ve "$C" > /dev/null
ok "stops in restore" "$(state)" "snapshot backup swap "
rm -f "$tmp/restore-fails" && : > "$calls"
rebuild_ve "$C" > /dev/null
ok "resume exit" "$?" 0
ok "all phases" "$(state)" "snapshot backup swap restore check "
ok "no backup on resume" "$(grep -c backup "$calls")" 0
ok "old tree kept" "$([[ -f $d/exrootfs/old-marker ]] && echo yes)" yes
ok "new tree in place" "$([[ -f $d/rootfs/new-marker && ! -e $d/newrootfs ]] && echo yes)" yes
ok "backup copied in" "$(cat "$d/rootfs/srv/backup/manifest")" "kind=wordpress"
ok "host key kept" "$([[ -f $d/rootfs/etc/ssh/ssh_host_ed25519_key ]] && echo yes)" yes
ok "was not running" "$(cat "$d/rebuild/was-running")" false
ok "before snapshot" "$(cat "$d/rebuild/before.status")" "200 My Site"

## rerun of a finished rebuild does nothing
rm -f "$calls"
rebuild_ve "$C" > /dev/null
ok "finished rerun is a no-op" "$(cat "$calls" 2> /dev/null)" ""

## check fails on a WordPress error page
echo '<title>WordPress</title> Error establishing a database connection' > "$tmp/page"
rebuild_ve "$C" check > /dev/null
ok "error page fails check" "$?" 1
echo '<html><title>My Site</title>' > "$tmp/page"

## a swap rerun after the renames only repeats the setup; without that record it never overwrites an exrootfs
: > "$calls" && rm -f "$tmp/running"
rebuild_ve_swap "$C" > /dev/null 2>&1
ok "swap rerun after the renames" "$?:$(tr '\n' ' ' < "$calls")" "0:init wp.example config wp.example "
mv "$d/rebuild/moved" "$tmp/moved"
rebuild_ve_swap "$C" > /dev/null 2>&1
ok "swap refuses over a foreign exrootfs" "$?" 1
mv "$tmp/moved" "$d/rebuild/moved"

## rollback puts the old tree back and leaves it stopped as it was
rebuild_ve "$C" rollback > /dev/null
ok "old tree back" "$([[ -f $d/rootfs/old-marker && ! -e $d/exrootfs ]] && echo yes)" yes
ok "new tree kept aside" "$([[ -f $d/rootfs.failed-now/new-marker ]] && echo yes)" yes
ok "state cleared" "$(state)" ""
ok "stopped as before" "$([[ -f $tmp/running ]] && echo yes)" ""
rebuild_ve "$C" discard-old > /dev/null
ok "discard-old needs a passed check" "$?" 1

## full run again, then discard-old removes the old trees
rm -rf "$d/rootfs/srv/backup"
rebuild_ve "$C" > /dev/null && rebuild_ve "$C" discard-old > /dev/null
ok "discarded" "$(ls -d "$d"/exrootfs "$d"/rootfs.failed-* 2> /dev/null)" ""
ok "closed, a later rebuild starts over" "$(state)$(compgen -G "$d/rebuild/state.done-*" | wc -l)" "1"

## a front page that was 403 before passes when unchanged, fails when it was 200 before
echo 403 > "$tmp/code" && echo '<title>Test Page</title>' > "$tmp/page"
echo '403 Test Page' > "$d/rebuild/before.status"
rebuild_ve_check "$C" > /dev/null
ok "same non-2xx as before passes" "$?" 0
echo '200 Test Page' > "$d/rebuild/before.status"
rebuild_ve_check "$C" > /dev/null
ok "new non-2xx fails" "$?" 1
rm -f "$tmp/code"

ok "unknown phase" "$(rebuild_ve "$C" bogus > /dev/null; echo $?)" 32

echo "rebuild: $pass passed, $fail failed"
((fail == 0))
