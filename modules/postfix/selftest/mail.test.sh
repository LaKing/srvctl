#!/bin/bash
# mail_ve target configuration and the mail queue helpers, with get/systemd/postfix mocks.
set -euo pipefail
SC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SRVCTL='test'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
SC_MAIL_VE_ROOT="$tmp/srv"
# shellcheck source=modules/postfix/libs/mailvelib.sh
source "$SC_INSTALL_DIR/modules/postfix/libs/mailvelib.sh"
# shellcheck source=modules/postfix/libs/mailqueuelib.sh
source "$SC_INSTALL_DIR/modules/postfix/libs/mailqueuelib.sh"

ve_map='' running=true
msg() { echo "$*" >> "$tmp/messages"; }
ntc() { echo "$*" >> "$tmp/messages"; }
err() { echo "$*" >> "$tmp/errors"; }
debug() { :; }
chown() { echo "chown $*" >> "$tmp/calls"; }
get() {
    case "$1 $2 ${3:-}" in
        'cluster mail_ve_map ') [[ -n $ve_map ]] || return 100; printf "%s" "$ve_map" ;;
        container*' uid') echo 7864320 ;;
        *) return 110 ;;
    esac
}
systemctl() { $running; }
## Stands in for the in-container script: record it, add the main.cf references.
systemd-run() {
    echo "systemd-run $2" >> "$tmp/calls"
    printf 'virtual_alias_domains = hash:%s\nvirtual_alias_maps = hash:%s\n' "${*: -2:1}" "${*: -1}" >> "$SC_MAIL_VE_ROOT/$2/rootfs/etc/postfix/main.cf"
}
expect() {
    [[ $2 == "$3" ]] || { echo "FAIL $1: expected '$2', got '$3'"; exit 1; }
    echo "PASS $1"
}
etc="$SC_MAIL_VE_ROOT/d250.hu/rootfs/etc/postfix"
mkdir -p "$etc" "$SC_MAIL_VE_ROOT/hangmaffia.hu/rootfs"
echo 'mydestination = localhost' > "$etc/main.cf"
: > "$tmp/calls"

ve_map=$'d250.hu hangmaffia.hu\nd250.hu hangmaffia.org\nelsewhere.hu x.hu\n'
regenerate_mail_ves
expect 'domains map' $'# srvctl mail_ve\nhangmaffia.hu OK\nhangmaffia.org OK' "$(cat "$etc/srvctl-mail-ve-domains")"
expect 'virtual map keeps the local part' $'# srvctl mail_ve\n@hangmaffia.hu @d250.hu\n@hangmaffia.org @d250.hu' "$(cat "$etc/srvctl-mail-ve")"
expect 'maps owned by the container root' 1 "$(grep -c 'chown 7864320:7864320' "$tmp/calls")"
expect 'applied inside the target once' 1 "$(grep -c 'systemd-run d250.hu' "$tmp/calls")"
expect 'target not on this host is skipped' 0 "$(grep -c elsewhere "$tmp/calls" || true)"

: > "$tmp/calls"
regenerate_mail_ves
expect 'unchanged maps do nothing' '' "$(cat "$tmp/calls")"

sed -i '/hash:/d' "$etc/main.cf"
regenerate_mail_ves
expect 'a rewritten main.cf gets the references back' 1 "$(grep -c 'systemd-run d250.hu' "$tmp/calls")"

: > "$tmp/calls"
ve_map=$'d250.hu hangmaffia.hu\n'
running=false
regenerate_mail_ves
expect 'stopped target is not written' '@hangmaffia.org @d250.hu' "$(grep -F hangmaffia.org "$etc/srvctl-mail-ve")"
expect 'stopped target is reported' 1 "$(grep -c 'is not running' "$tmp/messages")"

running=true
ve_map=''
regenerate_mail_ves
expect 'former target is emptied' '# srvctl mail_ve' "$(cat "$etc/srvctl-mail-ve")"

mkdir -p "$SC_MAIL_VE_ROOT/broken.hu/rootfs/etc/postfix"
echo 'mydestination = localhost' > "$SC_MAIL_VE_ROOT/broken.hu/rootfs/etc/postfix/main.cf"
ve_map=$'broken.hu a.hu\nd250.hu hangmaffia.hu\n'
real_systemd_run="$(declare -f systemd-run)"
systemd-run() { [[ $2 != broken.hu ]] || return 1; eval "${real_systemd_run/systemd-run/inner_run}"; inner_run "$@"; }
if regenerate_mail_ves; then echo 'FAIL broken target not reported'; exit 1; fi
expect 'a failing target does not stop the others' '@hangmaffia.hu @d250.hu' "$(grep -F hangmaffia.hu "$etc/srvctl-mail-ve")"
eval "$real_systemd_run"

## Queue: postqueue -j emits one JSON object per line.
postqueue() {
    cat << 'EOF'
{"queue_id":"A1","arrival_time":1760200000,"sender":"spam@x.example","recipients":[{"address":"pufi@hangmaffia.hu"}]}
{"queue_id":"A2","arrival_time":1760200000,"sender":"","recipients":[{"address":"Keresztapa@HANGMAFFIA.hu"},{"address":"pufi@hangmaffia.hu"}]}
{"queue_id":"A3","arrival_time":1760200000,"sender":"a@b.example","recipients":[{"address":"pufi@hangmaffia.hu"},{"address":"x@other.hu"}]}
{"queue_id":"A4","arrival_time":1760200000,"sender":"a@b.example","recipients":[{"address":"x@fox.hangmaffia.hu"}]}
{"queue_id":"A5","arrival_time":1760200000,"sender":"a@b.example"}
EOF
}
postcat() { printf 'Subject: hello %s\n' "${!#}"; }
postsuper() { cat > "$tmp/deleted"; }

expect 'select by exact domain' 'A1 A2 A3' "$(mail_queue_select hangmaffia.hu | awk '{ print $1 }' | paste -sd' ')"
expect 'every recipient in the domain' 'only only mixed' "$(mail_queue_select hangmaffia.hu | awk '{ print $2 }' | paste -sd' ')"
expect 'null sender shown' '<>' "$(mail_queue_select hangmaffia.hu | awk '$1 == "A2" { print $4 }')"
expect 'list shows the subject' 1 "$(list_mail_queue hangmaffia.hu | grep -c 'Subject: hello A1')"
delete_mail_queue_domain hangmaffia.hu > "$tmp/out"
expect 'only single-domain messages deleted' $'A1\nA2' "$(cat "$tmp/deleted")"
expect 'mixed message kept and named' 1 "$(grep -c 'kept, also for other domains: A3' "$tmp/out")"
if mail_queue_select 'bad domain;' 2> /dev/null; then echo 'FAIL invalid domain accepted'; exit 1; else expect 'invalid domain refused' 22 "$?"; fi

echo 'All postfix mail tests passed.'
