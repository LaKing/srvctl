#!/bin/bash
# regenerate_amavisd_ordering: the network-online drop-in is written once, with
# one daemon-reload; nothing where amavisd is not installed.
set -euo pipefail
SC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
# shellcheck disable=SC2034 # read by the sourced lib's guard
SRVCTL='test'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=modules/postfix/libs/postfixlib.sh
source "$SC_INSTALL_DIR/modules/postfix/libs/postfixlib.sh"
msg() { echo "$*" >> "$tmp/messages"; }
err() { echo "$*" >> "$tmp/errors"; }
systemctl() { echo "$*" >> "$tmp/systemctl"; }
expect() {
    [[ $2 == "$3" ]] || { echo "FAIL $1: expected '$2', got '$3'"; exit 1; }
    echo "PASS $1"
}
conf="$tmp/etc/amavisd.service.d/50-srvctl-network-online.conf"

SC_AMAVISD_UNIT="$tmp/no-such-unit"
regenerate_amavisd_ordering "$tmp/etc"
expect 'no amavisd: no drop-in' no "$([[ -e $conf ]] && echo yes || echo no)"

touch "$tmp/amavisd.service"
SC_AMAVISD_UNIT="$tmp/amavisd.service"
regenerate_amavisd_ordering "$tmp/etc"
expect 'after network-online' 'After=network-online.target' "$(grep '^After=' "$conf")"
expect 'wants network-online' 'Wants=network-online.target' "$(grep '^Wants=' "$conf")"
expect 'one daemon-reload' daemon-reload "$(cat "$tmp/systemctl")"
regenerate_amavisd_ordering "$tmp/etc"
expect 'second run: no reload' 1 "$(wc -l < "$tmp/systemctl")"
expect 'reported once' 1 "$(wc -l < "$tmp/messages")"
