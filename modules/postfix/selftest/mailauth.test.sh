#!/bin/bash
# Inbound mail authentication: gateway main.cf/master.cf milter topology, the
# forged-header strip rules, the generated SPF/DMARC/DKIM config and the
# Authentication-Results merger's callback sequence (stub Milter module).
# Needs postconf (postfix) and python3; postmap is used when it can run.
set -euo pipefail
SC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SRVCTL='test'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=modules/postfix/libs/mailauthlib.sh
source "$SC_INSTALL_DIR/modules/postfix/libs/mailauthlib.sh"
# shellcheck source=modules/opendkim/libs/opendkimlib.sh
source "$SC_INSTALL_DIR/modules/opendkim/libs/opendkimlib.sh"

msg() { echo "$*" >> "$tmp/messages"; }
err() { echo "$*" >> "$tmp/errors"; }
run() { echo "$*" >> "$tmp/calls"; }
systemctl() { echo "systemctl $*" >> "$tmp/calls"; }
expect() {
    [[ $2 == "$3" ]] || { echo "FAIL $1: expected '$2', got '$3'"; exit 1; }
    echo "PASS $1"
}
command -v postconf > /dev/null || { echo 'FAIL postconf (postfix) is required'; exit 1; }

## Templates, parsed by postfix itself.
pf="$tmp/postfix"
mkdir -p "$pf"
cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" "$pf/main.cf"
cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" "$pf/master.cf"
main() { postconf -c "$pf" -h "$1" 2> /dev/null; }
service() { postconf -c "$pf" -P -h "$1" 2> /dev/null; }
milter() { echo "inet:127.0.0.1:$1"; }

expect 'dead milter does not stop mail' accept "$(main milter_default_action)"
expect 'port 25: spf, dkim, dmarc in that order' \
    "$(milter "$MAILAUTH_SPF_PORT"), $(milter "$MAILAUTH_DKIM_PORT"), $(milter "$MAILAUTH_DMARC_PORT")" "$(main smtpd_milters)"
expect 'port 25 inherits the chain (container and AUTH signing)' '' "$(service smtp/inet/smtpd_milters)"
expect 'non-smtpd mail is signed' "$(milter "$MAILAUTH_DKIM_PORT")" "$(main non_smtpd_milters)"
expect 'smtps submission is signed' "$(milter "$MAILAUTH_DKIM_PORT")" "$(service smtps/inet/smtpd_milters)"
expect '10025 runs only the merger, no signing' "$(milter "$MAILAUTH_MERGE_PORT")" "$(service 127.0.0.1:10025/inet/smtpd_milters)"
expect '10025 keeps our fields (no header_checks)' no_header_body_checks "$(service 127.0.0.1:10025/inet/receive_override_options)"
expect 'header_checks file' "regexp:$MAILAUTH_HEADER_CHECKS" "$(main header_checks)"
expect 'attached messages are not edited' ':' "$(main mime_header_checks):$(main nested_header_checks)"
ports="$MAILAUTH_DKIM_PORT $MAILAUTH_SPF_PORT $MAILAUTH_DMARC_PORT $MAILAUTH_MERGE_PORT"
expect 'milter ports distinct' 4 "$(tr ' ' '\n' <<< "$ports" | sort -u | wc -l)"
expect 'no port is the packaged default 8893' 0 "$(tr ' ' '\n' <<< "$ports" | grep -c '^8893$' || true)"

## Strip rules: every incoming Authentication-Results and Received-SPF.
mailauth_header_checks > "$tmp/hc"
rules=()
while read -r line
do
    [[ $line == /* ]] || continue
    line="${line#/}"
    rules+=("${line%/ IGNORE}")
done < "$tmp/hc"
use_postmap=false
if postmap -q 'Received-SPF: x' "regexp:$tmp/hc" > /dev/null 2>&1
then
    use_postmap=true
else
    echo "NOTE postmap -q cannot run here; strip cases checked with bash regcomp only"
fi
strip() {
    local want="$1" h="$2" got='' re
    shopt -s nocasematch
    for re in "${rules[@]}"; do [[ $h =~ $re ]] && got=IGNORE; done
    shopt -u nocasematch
    expect "strip ${want:-keep}: ${h%%$'\n'*}" "$want" "$got"
    if $use_postmap
    then
        expect "postmap ${want:-keep}: ${h%%$'\n'*}" "$want" "$(postmap -q "$h" "regexp:$tmp/hc" 2> /dev/null || true)"
    fi
}
strip IGNORE 'Authentication-Results: r2.d250.hu; spf=pass smtp.mailfrom=d250.hu'
strip IGNORE 'Authentication-Results: srvctl-internal.invalid; spf=pass smtp.mailfrom=d250.hu'
strip IGNORE 'Authentication-Results: srvctl-internal . invalid; spf=pass smtp.mailfrom=d250.hu'
strip IGNORE 'Authentication-Results: srvctl-internal. (x) invalid; spf=pass smtp.mailfrom=d250.hu'
strip IGNORE 'Authentication-Results: "srvctl-internal.invalid"; dkim=pass header.d=d250.hu'
strip IGNORE 'Authentication-Results: ((nested)) r2.d250.hu; spf=pass'
strip IGNORE 'Authentication-Results: (a\)b) r2.d250.hu; spf=pass'
strip IGNORE 'Authentication-Results: "r2\.d250\.hu"; spf=pass'
strip IGNORE 'Authentication-Results: mx.google.com; spf=pass'
strip IGNORE 'authentication-results: R2.D250.HU;dkim=pass'
strip IGNORE 'AUTHENTICATION-RESULTS:x; dmarc=pass'
strip IGNORE 'Authentication-Results : r2.d250.hu; spf=pass'
strip IGNORE "$(printf 'Authentication-Results:\n\tsrvctl-internal.invalid;\n\tdmarc=pass')"
strip IGNORE 'Received-SPF: Pass (mailfrom) receiver=r2.d250.hu'
strip IGNORE 'received-spf : pass'
strip ''     'ARC-Authentication-Results: i=1; mx.google.com; spf=pass'
strip ''     'X-Authentication-Results: r2.d250.hu; spf=pass'
strip ''     'DKIM-Signature: v=1; d=d250.hu; h=from:to'
strip ''     'Subject: Authentication-Results: r2.d250.hu; spf=pass'

## OpenDKIM: verifies with the private id, signs internal hosts.
opendkim_conf "$MAILAUTH_INTERNAL_ID" > "$tmp/opendkim.conf"
for line in 'Mode        vs' "AuthservID        $MAILAUTH_INTERNAL_ID" 'AlwaysAddARHeader        yes' \
    'Socket        inet:8891@127.0.0.1' 'InternalHosts        refile:/var/opendkim/TrustedHosts'
do
    expect "opendkim.conf: $line" 1 "$(grep -cxF "$line" "$tmp/opendkim.conf")"
done
expect 'TrustedHosts seed keeps loopback and the farm' 2 \
    "$(grep -cE "^TrustedHosts \+= '(127\.0\.0\.1|10\.0\.0\.0/8)'" "$SC_INSTALL_DIR/modules/opendkim/opendkim.js")"

## Generated SPF/DMARC config, on package-like files.
MAILAUTH_HEADER_CHECKS="$tmp/etc/srvctl-auth-header-checks"
MAILAUTH_SPF_CONF="$tmp/etc/pyspf-milter/pyspf-milter.conf"
MAILAUTH_DMARC_CONF="$tmp/etc/opendmarc.conf"
MAILAUTH_DMARC_IGNORE="$tmp/etc/opendmarc/srvctl-ignore-hosts"
MAILAUTH_MERGE_UNIT="$tmp/etc/srvctl-armerge.service"
mkdir -p "$tmp/etc/pyspf-milter"
printf '%s\n' '# packaged' 'Socket = inet:8893@localhost' 'Mail_From_reject = Fail' 'HELO_reject = Fail' 'UserID = pyspf-milter' > "$MAILAUTH_SPF_CONF"
printf '%s\n' 'Socket inet:8893@localhost' '# RejectFailures false' 'UserID opendmarc:mail' > "$MAILAUTH_DMARC_CONF"
conf() { grep -E "^$2( |=)" "$1"; }
SC_HOSTNAME=r2.d250.hu
unset SC_MAIL_SPF_REJECT_HARDFAIL SC_MAIL_DMARC_HONOUR_POLICY
mailauth_install
expect 'spf: no reject on Mail From by default' 'Mail_From_reject = False' "$(conf "$MAILAUTH_SPF_CONF" Mail_From_reject)"
expect 'spf: no reject on HELO by default' 'HELO_reject = False' "$(conf "$MAILAUTH_SPF_CONF" HELO_reject)"
expect 'spf: socket' "Socket = inet:$MAILAUTH_SPF_PORT@127.0.0.1" "$(conf "$MAILAUTH_SPF_CONF" Socket)"
expect 'spf: records an AR header with the private id' "Header_Type = AR|Authserv_Id = $MAILAUTH_INTERNAL_ID" \
    "$(conf "$MAILAUTH_SPF_CONF" Header_Type)|$(conf "$MAILAUTH_SPF_CONF" Authserv_Id)"
expect 'spf: internal hosts not checked' 'InternalHosts = 127.0.0.0/8,::1,10.0.0.0/8,192.168.0.0/16' "$(conf "$MAILAUTH_SPF_CONF" InternalHosts)"
expect 'spf: packaged keys kept' 'UserID = pyspf-milter' "$(conf "$MAILAUTH_SPF_CONF" UserID)"
expect 'dmarc: record only by default' 'RejectFailures false' "$(conf "$MAILAUTH_DMARC_CONF" RejectFailures)"
expect 'dmarc: socket' "Socket inet:$MAILAUTH_DMARC_PORT@127.0.0.1" "$(conf "$MAILAUTH_DMARC_CONF" Socket)"
expect 'dmarc: trusts only the private id' "AuthservID $MAILAUTH_INTERNAL_ID|TrustedAuthservIDs $MAILAUTH_INTERNAL_ID" \
    "$(conf "$MAILAUTH_DMARC_CONF" AuthservID)|$(conf "$MAILAUTH_DMARC_CONF" TrustedAuthservIDs)"
expect 'dmarc: internal and authenticated clients ignored' "IgnoreHosts $MAILAUTH_DMARC_IGNORE|IgnoreAuthenticatedClients true" \
    "$(conf "$MAILAUTH_DMARC_CONF" IgnoreHosts)|$(conf "$MAILAUTH_DMARC_CONF" IgnoreAuthenticatedClients)"
expect 'dmarc: IgnoreHosts content' $'127.0.0.0/8\n::1\n10.0.0.0/8\n192.168.0.0/16' "$(cat "$MAILAUTH_DMARC_IGNORE")"
expect 'dmarc: packaged keys kept' 'UserID opendmarc:mail' "$(conf "$MAILAUTH_DMARC_CONF" UserID)"
expect 'header_checks file written' "$(mailauth_header_checks)" "$(cat "$MAILAUTH_HEADER_CHECKS")"
expect 'merger unit: gateway id and port' 1 \
    "$(grep -c -- "--socket inet:$MAILAUTH_MERGE_PORT@127.0.0.1 --authserv-id r2.d250.hu --internal-id $MAILAUTH_INTERNAL_ID" "$MAILAUTH_MERGE_UNIT")"
expect 'merger enabled and restarted' 1 "$(grep -c 'systemctl restart srvctl-armerge.service' "$tmp/calls")"

sums() { sha256sum "$MAILAUTH_HEADER_CHECKS" "$MAILAUTH_SPF_CONF" "$MAILAUTH_DMARC_CONF" "$MAILAUTH_DMARC_IGNORE" "$MAILAUTH_MERGE_UNIT"; }
before="$(sums)"
: > "$tmp/calls"
mailauth_install
expect 'second run changes nothing' "$before" "$(sums)"
expect 'unchanged unit is not reloaded' 0 "$(grep -c daemon-reload "$tmp/calls" || true)"
expect 'unchanged running services are not restarted' 0 "$(grep -c 'systemctl restart' "$tmp/calls" || true)"

: > "$tmp/calls"
SC_MAIL_SPF_REJECT_HARDFAIL=true SC_MAIL_DMARC_HONOUR_POLICY=true mailauth_install
expect 'setting change restarts spf and dmarc only' $'systemctl restart pyspf-milter.service\nsystemctl restart opendmarc.service' \
    "$(grep 'systemctl restart' "$tmp/calls")"
expect 'setting on: spf rejects hardfail' 'Mail_From_reject = Fail|HELO_reject = Fail' \
    "$(conf "$MAILAUTH_SPF_CONF" Mail_From_reject)|$(conf "$MAILAUTH_SPF_CONF" HELO_reject)"
expect 'setting on: dmarc honours the policy' 'RejectFailures true' "$(conf "$MAILAUTH_DMARC_CONF" RejectFailures)"
expect 'one line per key' 1 "$(grep -c '^RejectFailures' "$MAILAUTH_DMARC_CONF")"

SC_HOSTNAME=localhost
: > "$tmp/calls"
mailauth_install
expect 'dotless host name: reported' 1 "$(grep -c 'not a dotted DNS name' "$tmp/errors")"
expect 'dotless host name: merger disabled, not aborted' 'systemctl disable --now srvctl-armerge.service' "$(grep srvctl-armerge "$tmp/calls")"
expect 'dotless host name: strip rules still written' "$(mailauth_header_checks)" "$(cat "$MAILAUTH_HEADER_CHECKS")"
SC_HOSTNAME=''
HOSTNAME=''
if mailauth_authserv_id > /dev/null; then echo 'FAIL empty host name accepted'; exit 1; else echo 'PASS empty host name refused'; fi

## Merger: callback sequence with a stub Milter module (pymilter not needed).
python3 -I -B - "$SC_INSTALL_DIR/modules/postfix/apps/armerge.py" << 'PY'
import importlib.util, sys, types
spec = importlib.util.spec_from_file_location('armerge', sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Base:
    def __init__(self):
        self.calls = []
    def chgheader(self, name, idx, value):
        self.calls.append(('chg', name, idx, value))
    def addheader(self, name, value, idx=-1):
        self.calls.append(('add', name, value, idx))

Milter = types.SimpleNamespace(CONTINUE='CONTINUE', ACCEPT='ACCEPT', Base=Base)
logged = []
cls = mod.make_class(Milter, 'r2.d250.hu', 'srvctl-internal.invalid', logged.append)

def expect(label, want, got):
    if want != got:
        print('FAIL %s: expected %r, got %r' % (label, want, got))
        sys.exit(1)
    print('PASS ' + label)

m = cls()
seq = [m.envfrom('<a@gmail.com>')]
for name, value in [
        ('Received', 'from mail-lf1-f45.google.com'),
        ('Authentication-Results', 'srvctl-internal.invalid;\n\tdmarc=pass (p=none dis=none) header.from=gmail.com'),
        ('Authentication-Results', 'srvctl-internal.invalid; dkim=pass header.d=gmail.com header.b=AbCd'),
        ('Authentication-Results', 'srvctl-internal.invalid; spf=pass smtp.mailfrom=gmail.com'),
        ('Authentication-Results', 'r2.d250.hu (amavisd); dkim=pass'),
        ('Received-SPF', 'Pass'),
        ('Subject', 'hi')]:
    seq.append(m.header(name, value))
expect('merger: envfrom and header continue', ['CONTINUE'] * 8, seq)
expect('merger: eom accepts', 'ACCEPT', m.eom())
expect('merger: every A-R and Received-SPF deleted, highest first',
       [('chg', 'Authentication-Results', i, None) for i in (4, 3, 2, 1)] + [('chg', 'Received-SPF', 1, None)],
       [c for c in m.calls if c[0] == 'chg'])
adds = [c for c in m.calls if c[0] == 'add']
expect('merger: one field inserted at the top', [('Authentication-Results', 0)], [(c[1], c[3]) for c in adds])
expect('merger: spf, dkim, dmarc under the gateway id',
       'r2.d250.hu;\n\tspf=pass smtp.mailfrom=gmail.com;\n\tdkim=pass header.d=gmail.com header.b=AbCd;\n\tdmarc=pass (p=none dis=none) header.from=gmail.com',
       adds[0][2])
expect('merger: private id does not leak', False, 'srvctl-internal' in adds[0][2])

m.calls = []
expect('merger: next message on the connection starts clean', 'CONTINUE', m.envfrom('<b@x.example>'))
m.header('Authentication-Results', 'srvctl-internal.invalid; none')
m.header('Authentication-Results', 'srvctl-internal.invalid; dkim=none')
m.header('Authentication-Results', 'srvctl-internal.invalid; dmarc=none header.from=x.example')
m.header('Authentication-Results', 'srvctl-internal.invalid; spf=none smtp.mailfrom=x.example')
m.eom()
expect('merger: bare none skipped, dkim=none and dmarc=none kept',
       'r2.d250.hu;\n\tspf=none smtp.mailfrom=x.example;\n\tdkim=none;\n\tdmarc=none header.from=x.example',
       [c for c in m.calls if c[0] == 'add'][0][2])
expect('merger: only this message deleted', [4, 3, 2, 1], [c[2] for c in m.calls if c[0] == 'chg'])

m.calls = []
m.envfrom('<c@x.example>')
m.header('Authentication-Results', 'r2.d250.hu; spf=pass')
m.eom()
expect('merger: no private field, forged one removed, nothing added',
       [('chg', 'Authentication-Results', 1, None)], m.calls)
expect('merger: abort continues and resets', ('CONTINUE', []), (m.abort(), m.headers))

broken = cls()
def boom(*args):
    raise RuntimeError('boom')
broken.chgheader = boom
broken.envfrom('<d@x.example>')
broken.header('Authentication-Results', 'srvctl-internal.invalid; spf=pass')
expect('merger: failure still accepts', 'ACCEPT', broken.eom())
expect('merger: failure logged', 1, len(logged))
PY

echo 'All postfix mail authentication tests passed.'
