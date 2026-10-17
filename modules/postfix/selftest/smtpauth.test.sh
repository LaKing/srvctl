#!/bin/bash
# regenerate_smtp_auth: without the SMTP AUTH backend (perdition) the smtps
# listener is removed and smtpd_sasl_auth_enable set to no; with the backend
# nothing changes. Real postconf on an old-style config. Needs postfix.
set -euo pipefail
SC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
# shellcheck disable=SC2034 # read by the sourced lib's guard
SRVCTL='test'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=modules/postfix/libs/postfixlib.sh
source "$SC_INSTALL_DIR/modules/postfix/libs/postfixlib.sh"
msg() { echo "$*" >> "$tmp/messages"; }
expect() {
    [[ $2 == "$3" ]] || { echo "FAIL $1: expected '$2', got '$3'"; exit 1; }
    echo "PASS $1"
}
command -v postconf > /dev/null || { echo 'FAIL postconf (postfix) is required'; exit 1; }
smtps() { postconf -c "$1" -M smtps/inet 2> /dev/null | awk '{ print $1 }'; }
auth() { postconf -c "$1" -h smtpd_sasl_auth_enable 2> /dev/null; }

## The pre-change host config: smtps listener with SASL, AUTH on in main.cf.
fixture() {
    mkdir -p "$tmp/$1"
    cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" "$tmp/$1/main.cf"
    cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" "$tmp/$1/master.cf"
    postconf -c "$tmp/$1" -e 'smtpd_sasl_auth_enable = yes' 2> /dev/null
    postconf -c "$tmp/$1" -M 'smtps/inet=smtps inet n - n - - smtpd' 2> /dev/null
    postconf -c "$tmp/$1" -P 'smtps/inet/smtpd_sasl_auth_enable=yes' 2> /dev/null
}

fixture backend
SC_SMTP_AUTH_BACKEND=/bin/sh
regenerate_smtp_auth "$tmp/backend"
expect 'backend present: smtps kept' smtps "$(smtps "$tmp/backend")"
expect 'backend present: AUTH kept' yes "$(auth "$tmp/backend")"

fixture none
SC_SMTP_AUTH_BACKEND="$tmp/no-such-perdition"
regenerate_smtp_auth "$tmp/none"
expect 'no backend: smtps removed' '' "$(smtps "$tmp/none")"
expect 'no backend: AUTH off' no "$(auth "$tmp/none")"
expect 'no backend: smtp listener kept' smtp "$(postconf -c "$tmp/none" -M smtp/inet 2> /dev/null | awk '{ print $1 }')"
expect 'no backend: both changes reported' 2 "$(grep -c 'no SMTP AUTH backend\|no backend (perdition)' "$tmp/messages")"
before="$(sha256sum "$tmp/none/main.cf" "$tmp/none/master.cf")"
regenerate_smtp_auth "$tmp/none"
expect 'second run changes nothing' "$before" "$(sha256sum "$tmp/none/main.cf" "$tmp/none/master.cf")"

mkdir -p "$tmp/template"
cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" "$tmp/template/main.cf"
cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" "$tmp/template/master.cf"
expect 'template: no smtps, AUTH off' ':no' "$(smtps "$tmp/template"):$(auth "$tmp/template")"

echo 'All postfix SMTP AUTH tests passed.'
