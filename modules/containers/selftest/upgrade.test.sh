#!/bin/bash
# libs/upgradelib.sh phase machine against a fake /srv and base image, with systemctl,
# machinectl, systemd-nspawn, ssh, curl and df stubbed: refusals, repo URLs, lost
# enabled links, the service check, rollback, discard-old. dnf itself is not run.
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
C=app.example d="$tmp/srv/app.example" r="$tmp/srv/app.example/rootfs" w=etc/systemd/system/multi-user.target.wants

msg() { echo "$*"; }
ntc() { echo "$*"; }
err() { echo "ERR $*"; }
# shellcheck disable=SC2048 ## as lablib's run: unquoted, so an argument with spaces would break here too
run() { $*; }
sleep() { :; }
timeout() { :; }
machinectl() { case $1 in show) [[ -f $tmp/running ]] ;; *) rm -f "$tmp/running" ;; esac; }
systemctl() { case $1 in start) touch "$tmp/running" ;; stop) rm -f "$tmp/running" ;; esac; }
df() { echo Avail; cat "$tmp/avail" 2> /dev/null || echo 999999999999; }
curl() {
    local out
    while (($#)); do [[ $1 == -o ]] && out="$2"; shift; done
    echo '<html><title>App</title>' > "$out"
    echo 200
}
## the upgrade: new release, a dropped wants link, a new default config
systemd-nspawn() {
    echo "$*" > "$tmp/nspawn"
    [[ ${*: -1} == "dnf -y upgrade"* ]] || return 2 ## the script reached bash -c in one piece
    [[ -f $tmp/dnf-fails ]] && return 1
    echo 'VERSION_ID=44' > "$r/usr/lib/os-release"
    rm -f "$r/$w/postfix.service" "$r/$w/gone.service"
    touch "$r/etc/caddy.rpmnew"
}
# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/rebuildlib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/upgradelib.sh"

## running: caddy (started by hand) and sshd before; afterwards whatever $tmp/active lists
rebuild_ssh() {
    [[ -f $tmp/running ]] || return 255
    case "${2:-}" in
        *list-units*) printf '%s\n' 'caddy.service loaded active running' 'sshd.service loaded active running' 'user@0.service loaded active running' ;;
        *is-active*) [[ $2 =~ \'(.*)\' ]] && grep -qx "${BASH_REMATCH[1]}" "$tmp/active" ;;
        *is-enabled*) false ;;
        *) true ;;
    esac
}

mkdir -p "$tmp/rootfs/fedora/usr/lib"
echo VERSION_ID=44 > "$tmp/rootfs/fedora/usr/lib/os-release"
newold() { ## release
    rm -rf "$d" && mkdir -p "$r/usr/lib" "$r/etc/yum.repos.d" "$r/$w" "$r/usr/lib/systemd/system"
    printf 'ID=fedora\nVERSION_ID=%s\n' "$1" > "$r/usr/lib/os-release"
    printf '[zerotier]\nbaseurl=https://download.zerotier.com/redhat/fc/%s\ngpgkey=https://x/%s.gpg\n' "$1" "$1" > "$r/etc/yum.repos.d/zerotier.repo"
    printf '[fedora]\nmetalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-%s\n' "$1" > "$r/etc/yum.repos.d/fedora.repo"
    touch "$r/old-marker" "$r/usr/lib/systemd/system/postfix.service"
    ln -s /usr/lib/systemd/system/postfix.service "$r/$w/postfix.service"
    ln -s /usr/lib/systemd/system/gone.service "$r/$w/gone.service"
    echo sshd.service > "$tmp/active"
    touch "$tmp/running"
}
state() { tr '\n' ' ' 2> /dev/null < "$d/upgrade/state"; }

## refusals before anything changes
newold 41
ok "3 releases behind refused" "$(upgrade_ve "$C" | grep -c 'more than 2 releases')" 1
ok "nothing recorded" "$(state)" ""
newold 43 && echo 10 > "$tmp/avail"
ok "no disk space refused" "$(upgrade_ve "$C" | grep -c 'free for the copy')" 1
rm -f "$tmp/avail"
newold 43 && sed -i 's/^ID=fedora/ID=debian/' "$r/usr/lib/os-release"
ok "not fedora refused" "$(upgrade_ve "$C" | grep -c 'not a Fedora')" 1

## a failing dnf stops in upgrade with the copy made; the rerun continues there
newold 43 && touch "$tmp/dnf-fails"
upgrade_ve "$C" > /dev/null
ok "stops in upgrade" "$(state)" "prepare copy "
ok "copy made" "$([[ -f $d/exrootfs/old-marker && ! -e $d/exrootfs.partial ]] && echo yes)" yes
ok "stopped for dnf" "$([[ -f $tmp/running ]] && echo yes)" ""
rm -f "$tmp/dnf-fails"
out="$(upgrade_ve "$C")"
ok "check fails on the hand-started service" "$(grep -c 'caddy.service ran before the upgrade' <<< "$out")" 1
ok "phases up to check" "$(state)" "prepare copy upgrade "
ok "systemctl offline in the nspawn" "$(grep -c -- '--setenv=SYSTEMD_OFFLINE=1' "$tmp/nspawn")" 1
ok "maps the tree's uid base" "$(grep -c -- "--private-users=$(stat -c %u "$r"):65536" "$tmp/nspawn")" 1
ok "release in the repo URL" "$(grep baseurl "$r/etc/yum.repos.d/zerotier.repo")" "baseurl=https://download.zerotier.com/redhat/fc/44"
ok "fedora repo left to dnf" "$(grep -c 'fedora-43' "$r/etc/yum.repos.d/fedora.repo")" 1
ok "dropped link put back" "$(readlink "$r/$w/postfix.service")" /usr/lib/systemd/system/postfix.service
ok "link of a gone unit named" "$(grep -c 'gone.service was enabled' <<< "$out")" 1
ok "rpmnew named" "$(grep -c '/etc/caddy.rpmnew' <<< "$out")" 1
ok "login sessions not expected" "$(grep -c 'user@0' "$d/upgrade/expected-services")" 0
ok "front page before" "$(cat "$d/upgrade/before.status")" "200 App"

## rebuild-ve does not take the upgrade's copy
ok "rebuild rollback refused" "$(rebuild_ve "$C" rollback | grep -c 'open upgrade-ve')" 1
ok "discard-old needs a passed check" "$(upgrade_ve "$C" discard-old > /dev/null; echo $?)" 1

## enabled and running now: check passes, discard-old closes the run
echo caddy.service >> "$tmp/active"
upgrade_ve "$C" > /dev/null
ok "resume passes" "$(state)" "prepare copy upgrade check "
upgrade_ve "$C" discard-old > /dev/null
ok "copy discarded" "$([[ -e $d/exrootfs ]] && echo yes)$(state)" ""

## rollback puts the copy back and starts it as it was running
newold 43 && touch "$tmp/dnf-fails"
upgrade_ve "$C" > /dev/null
rm -f "$tmp/dnf-fails" "$tmp/running"
upgrade_ve "$C" rollback > /dev/null
ok "old tree back" "$(upgrade_release_of "$r")" 43
ok "failed tree kept" "$([[ -d $d/rootfs.failed-now ]] && echo yes)" yes
ok "running again" "$([[ -f $tmp/running ]] && echo yes)" yes
ok "run closed" "$(state)" ""
ok "rollback twice refused" "$(upgrade_ve "$C" rollback > /dev/null; echo $?)" 1

## the same release is a repair, not a refusal
newold 44 && mkdir -p "$d/upgrade"
upgrade_ve_prepare "$C" > /dev/null
ok "same release allowed" "$?" 0

ok "unknown phase" "$(upgrade_ve "$C" bogus > /dev/null; echo $?)" 32

echo "upgrade: $pass passed, $fail failed"
((fail == 0))
