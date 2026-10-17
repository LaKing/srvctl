#!/bin/bash
# regenerate_reinjection_milters: the amavis reinjection listener gets an empty
# smtpd_milters override on an old-style master.cf, keeps a safe override, and
# loses one that still names opendkim. Needs postconf (postfix).
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
expect() {
    [[ $2 == "$3" ]] || { echo "FAIL $1: expected '$2', got '$3'"; exit 1; }
    echo "PASS $1"
}
command -v postconf > /dev/null || { echo 'FAIL postconf (postfix) is required'; exit 1; }
svc=127.0.0.1:10025/inet/smtpd_milters
override() { postconf -c "$1" -P 2> /dev/null | awk -v k="$svc" '$1 == k { sub(/^[^=]*= ?/, ""); print "set:" $0 }'; }
fixture() {
    mkdir -p "$tmp/$1"
    cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" "$tmp/$1/"
    mv "$tmp/$1/hs-main.cf" "$tmp/$1/main.cf"
    mv "$tmp/$1/hs-master.cf" "$tmp/$1/master.cf"
    postconf -c "$tmp/$1" -PX "$svc" 2> /dev/null
    [[ -z ${2:-} ]] || postconf -c "$tmp/$1" -P "$svc=$2" 2> /dev/null
}

## r2 today: no override, so 10025 inherits smtpd_milters (opendkim).
fixture old
regenerate_reinjection_milters "$tmp/old"
expect 'old: empty override set' 'set:' "$(override "$tmp/old")"
expect 'old: reported' 1 "$(grep -c 'no milters on the 127.0.0.1:10025 reinjection' "$tmp/messages")"
before="$(sha256sum "$tmp/old/master.cf")"
regenerate_reinjection_milters "$tmp/old"
expect 'old: second run changes nothing' "$before" "$(sha256sum "$tmp/old/master.cf")"
expect 'other services untouched' 'inet:127.0.0.1:8891' "$(postconf -c "$tmp/old" -P -h smtps/inet/smtpd_milters 2> /dev/null)"

fixture merger inet:127.0.0.1:8895
regenerate_reinjection_milters "$tmp/merger"
expect 'merger override kept' 'set:inet:127.0.0.1:8895' "$(override "$tmp/merger")"

fixture signing inet:127.0.0.1:8891
regenerate_reinjection_milters "$tmp/signing"
expect 'opendkim override removed' 'set:' "$(override "$tmp/signing")"

# shellcheck disable=SC2016 # a literal postfix $parameter reference
fixture indirect '$non_smtpd_milters'
regenerate_reinjection_milters "$tmp/indirect"
expect 'indirect parameter override removed' 'set:' "$(override "$tmp/indirect")"

## No reinjection listener: reported, nothing invented.
mkdir -p "$tmp/none"
cp "$tmp/old/main.cf" "$tmp/none/"
postconf -c "$tmp/old" -M smtp/inet > "$tmp/none/master.cf" 2> /dev/null
regenerate_reinjection_milters "$tmp/none"
expect 'no listener: reported' 1 "$(grep -c 'no \*:10025 reinjection listener' "$tmp/errors")"
expect 'no listener: none invented' '' "$(postconf -c "$tmp/none" -M 2> /dev/null | grep 10025 || true)"

echo 'All postfix reinjection tests passed.'
