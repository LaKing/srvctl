#!/bin/bash
# Inbound mail authentication on the regenerate path: the targeted postfix key
# update on an old-style main.cf/master.cf, the opendkim.conf key update,
# service restarts only on change, and package installation of missing ones.
# Needs postconf (postfix); systemctl, rpm and dnf are stubbed.
set -euo pipefail
SC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SRVCTL='test'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=modules/postfix/libs/mailauthlib.sh
source "$SC_INSTALL_DIR/modules/postfix/libs/mailauthlib.sh"
# shellcheck source=modules/postfix/libs/mailauthregeneratelib.sh
source "$SC_INSTALL_DIR/modules/postfix/libs/mailauthregeneratelib.sh"
# shellcheck source=modules/opendkim/libs/opendkimlib.sh
source "$SC_INSTALL_DIR/modules/opendkim/libs/opendkimlib.sh"

msg() { :; }
err() { echo "$*" >> "$tmp/errors"; }
run() { echo "$*" >> "$tmp/calls"; }
restart_opendkim() { echo restart_opendkim >> "$tmp/calls"; }
sc_install() { echo "sc_install $*" >> "$tmp/calls"; }
active=yes
units='pyspf-milter.service opendmarc.service srvctl-armerge.service'
systemctl() {
    case "$1" in
        cat) [[ " $units " == *" $2 "* ]] ;;
        is-active) [[ $active == yes ]] ;;
        is-enabled) return 0 ;;
        *) echo "systemctl $*" >> "$tmp/calls" ;;
    esac
}
expect() {
    [[ $2 == "$3" ]] || { echo "FAIL $1: expected '$2', got '$3'"; exit 1; }
    echo "PASS $1"
}
count() { grep -c -- "$1" "$2" 2> /dev/null || true; }
command -v postconf > /dev/null || { echo 'FAIL postconf (postfix) is required'; exit 1; }

## An old-style live config: the templates with the pre-mailauth milter keys
## and one local edit that must survive.
tpl="$tmp/tpl" live="$tmp/live"
mkdir -p "$tpl" "$live"
cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" "$tpl/main.cf"
cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" "$tpl/master.cf"
cp "$tpl/main.cf" "$tpl/master.cf" "$live/"
postconf -c "$live" -X header_checks mime_header_checks nested_header_checks 2> /dev/null
# shellcheck disable=SC2016 # a literal postfix $parameter reference
postconf -c "$live" -e 'smtpd_milters = inet:127.0.0.1:8891' 'non_smtpd_milters = $smtpd_milters' 'myorigin = local.example' 2> /dev/null
postconf -c "$live" -PX smtps/inet/smtpd_milters 127.0.0.1:10025/inet/smtpd_milters 127.0.0.1:10025/inet/receive_override_options 2> /dev/null
expect 'fixture: old live config differs' 1 "$( [[ $(postconf -c "$live" -h smtpd_milters 2> /dev/null) != "$(postconf -c "$tpl" -h smtpd_milters 2> /dev/null)" ]] && echo 1)"

out="$(mailauth_postfix_conf "$live")"
for key in "${MAILAUTH_MAIN_KEYS[@]}"
do
    expect "main.cf $key" "$(postconf -c "$tpl" -h "$key" 2> /dev/null)" "$(postconf -c "$live" -h "$key" 2> /dev/null)"
done
for key in "${MAILAUTH_MASTER_KEYS[@]}"
do
    expect "master.cf $key" "$(postconf -c "$tpl" -P -h "$key" 2> /dev/null)" "$(postconf -c "$live" -P -h "$key" 2> /dev/null)"
done
expect 'nested_header_checks no longer inherits the strip' '' "$(postconf -c "$live" -h nested_header_checks 2> /dev/null)"
expect 'local edit kept' local.example "$(postconf -c "$live" -h myorigin 2> /dev/null)"
expect 'changes reported' 1 "$( [[ $out == *'main.cf: smtpd_milters = '* && $out == *'master.cf: 127.0.0.1:10025/inet/smtpd_milters = '* ]] && echo 1)"
before="$(sha256sum "$live/main.cf" "$live/master.cf")"
expect 'second run reports nothing' '' "$(mailauth_postfix_conf "$live")"
expect 'second run changes nothing' "$before" "$(sha256sum "$live/main.cf" "$live/master.cf")"

## A host whose master.cf lacks the reinjection service: reported, the rest set.
nr="$tmp/noreinject"
mkdir -p "$nr"
cp "$tpl/main.cf" "$nr/"
postconf -c "$tpl" -M smtp/inet smtps/inet > "$nr/master.cf" 2> /dev/null
postconf -c "$nr" -PX smtps/inet/smtpd_milters 2> /dev/null
mailauth_postfix_conf "$nr" > /dev/null
expect 'missing 10025 service reported' 2 "$(count '127.0.0.1:10025' "$tmp/errors")"
expect 'smtps still set' "$(postconf -c "$tpl" -P -h smtps/inet/smtpd_milters 2> /dev/null)" "$(postconf -c "$nr" -P -h smtps/inet/smtpd_milters 2> /dev/null)"
expect 'no 10025 service invented' '' "$(postconf -c "$nr" -M 127.0.0.1:10025/inet 2> /dev/null)"

## opendkim.conf from an old update-install: two keys added, other lines kept.
dkim="$tmp/opendkim.conf"
opendkim_conf x | grep -v -e '^AuthservID' -e '^AlwaysAddARHeader' > "$dkim"
echo 'LocalEdit        kept' >> "$dkim"
: > "$tmp/calls"
regenerate_opendkim_conf "$MAILAUTH_INTERNAL_ID" "$dkim"
expect 'opendkim: AuthservID set' "AuthservID $MAILAUTH_INTERNAL_ID" "$(grep -E '^AuthservID' "$dkim")"
expect 'opendkim: AlwaysAddARHeader set' 'AlwaysAddARHeader yes' "$(grep -E '^AlwaysAddARHeader' "$dkim")"
expect 'opendkim: local edit kept' 1 "$(count '^LocalEdit' "$dkim")"
expect 'opendkim: restarted on change' 1 "$(count restart_opendkim "$tmp/calls")"
regenerate_opendkim_conf "$MAILAUTH_INTERNAL_ID" "$dkim"
expect 'opendkim: no restart when unchanged' 1 "$(count restart_opendkim "$tmp/calls")"

## mailauth_regenerate: missing packages installed, config written once,
## services restarted only on change or when not running.
MAILAUTH_HEADER_CHECKS="$tmp/etc/srvctl-auth-header-checks"
MAILAUTH_SPF_CONF="$tmp/etc/pyspf-milter/pyspf-milter.conf"
MAILAUTH_DMARC_CONF="$tmp/etc/opendmarc.conf"
MAILAUTH_DMARC_IGNORE="$tmp/etc/opendmarc/srvctl-ignore-hosts"
MAILAUTH_MERGE_UNIT="$tmp/etc/srvctl-armerge.service"
SC_HOSTNAME=r2.d250.hu
mkdir -p "$tmp/etc"
installed=' python3-pymilter '
rpm() { [[ $installed == *" $2 "* ]]; }
mailauth_postfix_conf() { :; }
: > "$tmp/calls"
mailauth_regenerate
expect 'missing packages installed' 'sc_install pypolicyd-spf-milter opendmarc publicsuffix-list' "$(grep sc_install "$tmp/calls")"
for unit in pyspf-milter opendmarc srvctl-armerge
do
    expect "first run restarts $unit" 1 "$(count "systemctl restart $unit.service" "$tmp/calls")"
done

installed=" ${MAILAUTH_PACKAGES[*]} "
: > "$tmp/calls"
mailauth_regenerate
expect 'steady state: no install, no restart' '' "$(cat "$tmp/calls")"

active=no
mailauth_regenerate
expect 'stopped services are started' 3 "$(count 'systemctl restart' "$tmp/calls")"

active=yes units='opendmarc.service srvctl-armerge.service'
: > "$tmp/errors"
mailauth_regenerate
expect 'missing unit reported, not fatal' 1 "$(count 'pyspf-milter.service is not installed' "$tmp/errors")"

echo 'All postfix mail authentication regenerate tests passed.'
