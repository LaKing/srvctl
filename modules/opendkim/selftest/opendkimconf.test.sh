#!/bin/bash
# regenerate_opendkim_conf (libs/opendkimlib.sh): the signing-policy target of
# /etc/opendkim.conf and the Postfix settings it depends on. Real postconf and
# postmap on copies of conf/hs-main.cf and hs-master.cf; a fake `opendkim -V`
# (SC_OPENDKIM_BIN) with or without USE_LUA; restart stubs that record the
# order and the opendkim.conf state at each opendkim restart. Every row runs
# twice: the second run must change no file and restart nothing.
# Needs postfix (postconf, postmap).
# shellcheck disable=SC2016 # literal postfix $parameter references throughout
set -uo pipefail
SC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
# shellcheck disable=SC2034 # read by the sourced lib
SRVCTL='test'
HOSTNAME=testhost
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=modules/opendkim/libs/opendkimlib.sh
source "$SC_INSTALL_DIR/modules/opendkim/libs/opendkimlib.sh"
command -v postconf > /dev/null || { echo 'FAIL postconf (postfix) is required'; exit 1; }

failed=0
msg() { echo "$*" >> "$tmp/messages"; }
err() { echo "$*" >> "$tmp/errors"; }
expect() {
    if [[ $2 == "$3" ]]
    then
        echo "PASS $ROW: $1"
    else
        echo "FAIL $ROW: $1: expected '$2', got '$3'"
        failed=1
    fi
}
expect_grep() { # name pattern file
    if grep -q -- "$2" "$3" 2> /dev/null
    then
        echo "PASS $ROW: $1"
    else
        echo "FAIL $ROW: $1: no '$2' in $(basename "$3"): $(tail -n 3 "$3" 2> /dev/null)"
        failed=1
    fi
}

printf '#!/bin/sh\necho "opendkim: OpenDKIM Filter v2.11.0"\necho "\tCompiled with OpenSSL"\necho "\tActive code options:"\necho "\t\tUSE_LUA"\n' > "$tmp/opendkim-lua"
printf '#!/bin/sh\necho "opendkim: OpenDKIM Filter v2.11.0"\necho "\tActive code options:"\necho "\t\tQUERY_CACHE"\n' > "$tmp/opendkim-nolua"
chmod +x "$tmp/opendkim-lua" "$tmp/opendkim-nolua"
lua() { SC_OPENDKIM_BIN="$tmp/opendkim-lua"; }
nolua() { SC_OPENDKIM_BIN="$tmp/opendkim-nolua"; }
export SC_OPENDKIM_BIN

key() { awk -v k="$1" 'tolower($1) == tolower(k) { print $2 }' "$CONF"; }
## restart stubs: the order and the state at each restart
restart_opendkim() {
    local script=no
    [[ -n $(key SetupPolicyScript) ]] && script=yes
    echo "opendkim-restart $(key SigningTable) $script" >> "$LOG"
}
eval "real_restart_postfix() $(declare -f opendkim_restart_postfix | tail -n +2)"
opendkim_restart_postfix() {
    echo "postfix-restart $(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum | cut -c1-16)" >> "$LOG"
    return "${PF_RC:-0}"
}

QUIET='refile:/var/opendkim/EmptySigningTable no'
HOSTTABLE='refile:/var/opendkim/HostSigningTable'
M='i {mail_addr} {mail_host} {mail_mailer}'

## a row: opendkim.conf from the update-install heredoc, postfix from the templates
row() {
    ROW="$1" DIR="$tmp/$1/postfix" CONF="$tmp/$1/opendkim.conf"
    export SC_OPENDKIM_POLICY="$tmp/$1/srvctl-signing-policy.lua"
    mkdir -p "$DIR"
    cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" "$DIR/main.cf"
    cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" "$DIR/master.cf"
    sed -n '/^cat > \/etc\/opendkim.conf << EOF$/,/^EOF$/p' "$SC_INSTALL_DIR/modules/opendkim/hooks/update-install-host.sh" | sed '1d;$d' > "$CONF"
    PF_RC=0
}
## continue from the end state of another row
from() {
    local src="$tmp/$1"
    ROW="$2" DIR="$tmp/$2/postfix" CONF="$tmp/$2/opendkim.conf"
    export SC_OPENDKIM_POLICY="$tmp/$2/srvctl-signing-policy.lua"
    cp -a "$src" "$tmp/$2"
    ## srvctl's map setting names its own directory; follow the move
    sed -i -E "s|$tmp/[^/]+/postfix/|$tmp/$2/postfix/|g" "$DIR/main.cf" "$DIR/master.cf"
    PF_RC=0
}
pce() { postconf -c "$DIR" "$@" 2> /dev/null; }
mainv() { awk -F' = ' -v k="$1" '$1 == k { v = $2 } END { print v }' <(pce -n); }
ovr() { local v; v="$(pce -P | awk -v k="$1" '$1 == k { sub(/^[^=]*= ?/, ""); print "set:" $0 }')"; echo "${v:-unset}"; }
smtps() {
    pce -M 'smtps/inet=smtps inet n - n - - smtpd'
    pce -P 'smtps/inet/smtpd_sasl_auth_enable=yes'
}
sum() {
    { cat "$CONF" "$DIR/main.cf" "$DIR/master.cf" "$DIR/srvctl-milter-map" "$DIR/srvctl-isolated-listeners" "$SC_OPENDKIM_POLICY" 2> /dev/null
      [[ -e $DIR/srvctl-postfix-restart-pending ]] && echo PENDING; } | sha256sum
}
go() { # one regenerate; log in $LOG
    LOG="$tmp/$ROW.log.$1"
    : > "$LOG"
    : > "$tmp/errors"
    regenerate_opendkim_conf "$CONF" "$DIR"
}
## run twice: run 1, then run 2 must change nothing and restart nothing
twice() {
    local s1
    go 1
    s1="$(sum)"
    CASE1="$OPENDKIM_CASE"
    cp "$tmp/errors" "$tmp/$ROW.errors"
    go 2
    expect 'run 2: same files' "$s1" "$(sum)"
    expect 'run 2: no restart' '' "$(cat "$LOG")"
    expect 'run 2: same case' "$CASE1" "$OPENDKIM_CASE"
    expect 'no pending marker' no "$([[ -e $DIR/srvctl-postfix-restart-pending ]] && echo yes || echo no)"
    LOG="$tmp/$ROW.log.1"
    cp "$tmp/$ROW.errors" "$tmp/errors"
}
## run 1 must have restarted postfix before opendkim left the quiet state,
## with the Postfix edits already in the files
ordered() {
    local final ok
    final="$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum | cut -c1-16)"
    ok="$(awk -v q="$QUIET" -v f="$final" '
        /^postfix-restart/ { p = 1; if ($2 != f) stale = 1; next }
        /^opendkim-restart/ { s = $2 " " $3; if (s != q) { if (!p) bad = 1; else on = 1 } }
        END { print (p && on && !bad && !stale) ? "ordered" : "NOT ordered" }' "$LOG")"
    expect "postfix restarted (with the edits in place) before opendkim left quiet [$(tr '\n' ';' < "$LOG")]" ordered "$ok"
}
state() { # target opendkim.conf state
    local script=no
    [[ -n $(key SetupPolicyScript) ]] && script=yes
    expect "opendkim.conf: $1" "$1" "$(key SigningTable) $script"
}
case_is() { expect "case $1" "$1" "$OPENDKIM_CASE"; }
pickup_signs() { expect 'pickup still reaches opendkim' 'inet:127.0.0.1:8891' "$(pce -xh non_smtpd_milters)"; }

## ---------------------------------------------------------------------------
## Resolver (AC4a), per service context
ROW=resolver
row R
pce -e 'lit = inet:127.0.0.1:9999' 'one = $lit' 'b = inet:127.0.0.1:8891' 'two = $three' 'three = $b' 'cond = ${nope?x}'
pce -P 'smtp/inet/smtpd_milters=$one'
opendkim_pf_load "$DIR"
opendkim_pf_eval '' lit;   ROW=R1; expect 'literal' 'ok inet:127.0.0.1:9999' "$OPENDKIM_PF_STATE $OPENDKIM_PF_VALUE"
opendkim_pf_eval '' one;   ROW=R2; expect '$a -> literal' 'ok inet:127.0.0.1:9999' "$OPENDKIM_PF_STATE $OPENDKIM_PF_VALUE"
opendkim_pf_eval '' two;   ROW=R3; expect '$a -> $b -> :8891' 'ok inet:127.0.0.1:8891' "$OPENDKIM_PF_STATE $OPENDKIM_PF_VALUE"
pce -e 'undef = $undefined_thing'; opendkim_pf_load "$DIR"
opendkim_pf_eval '' undef; ROW=R4; expect 'undefined name' unresolved "$OPENDKIM_PF_STATE"
opendkim_pf_eval '' cond;  ROW=R5; expect 'conditional form' unresolved "$OPENDKIM_PF_STATE"
OPENDKIM_PF_MAIN[ca]='$cb' OPENDKIM_PF_MAIN[cb]='$ca'
opendkim_pf_eval '' ca;    ROW=R6; expect 'cycle' 'unresolved cycle through $ca' "$OPENDKIM_PF_STATE $OPENDKIM_PF_WHY"
OPENDKIM_PF_MAIN[host]='$myhostname'
opendkim_pf_eval '' host;  ROW=R7; expect 'built-in default' ok "$OPENDKIM_PF_STATE"
opendkim_pf_load "$DIR"
opendkim_pf_eval smtp/inet smtpd_milters; ROW=R8; expect 'override with $a' 'ok inet:127.0.0.1:9999' "$OPENDKIM_PF_STATE $OPENDKIM_PF_VALUE"
row R9
pce -e 'my_chain = inet:127.0.0.1:9999'
pce -P 'smtp/inet/my_chain=$undefined_thing' 'smtp/inet/smtpd_milters=$my_chain'
opendkim_pf_load "$DIR"; opendkim_pf_eval smtp/inet smtpd_milters
expect 'service-shadowed chain to an undefined name (postconf -Px says empty)' 'unresolved|' "$OPENDKIM_PF_STATE|${OPENDKIM_PF_PX[smtp/inet/smtpd_milters]}"
row R10
pce -e 'my_macros = i {auth_type} {auth_authen} {mail_addr}' 'milter_mail_macros = $my_macros'
pce -P 'smtp/inet/my_macros=i,{auth_type}'
opendkim_pf_load "$DIR"; opendkim_pf_eval smtp/inet milter_mail_macros
expect 'inherited macros through a service-shadowed name' 'ok i,{auth_type}' "$OPENDKIM_PF_STATE $OPENDKIM_PF_VALUE"
row R11
pce -e 'my_chain = inet:127.0.0.1:9999'
pce -P 'smtp/inet/my_chain=inet:127.0.0.1:8891' 'smtp/inet/smtpd_milters=$my_chain'
opendkim_pf_load "$DIR"; opendkim_pf_eval smtp/inet smtpd_milters
expect 'service shadow to a defined literal' 'ok inet:127.0.0.1:8891' "$OPENDKIM_PF_STATE $OPENDKIM_PF_VALUE"
OPENDKIM_PF_PX[smtp/inet/smtpd_milters]='something else'
opendkim_pf_eval smtp/inet smtpd_milters; ROW=R12
expect 'srvctl and postconf disagree' "unresolved postconf expands smtp/inet/smtpd_milters differently" "$OPENDKIM_PF_STATE $OPENDKIM_PF_WHY"

## ---------------------------------------------------------------------------
## Lua-capable (case A)
lua
row S1; twice; case_is A; state 'refile:/var/opendkim/EmptySigningTable yes'
expect 'policy script installed' same "$(cmp -s "$SC_OPENDKIM_POLICY" "$SC_INSTALL_DIR/modules/opendkim/conf/signing-policy.lua" && echo same)"
expect 'no milter_mail_macros in main.cf' '' "$(mainv milter_mail_macros)"
expect 'no smtpd_milter_maps in main.cf' '' "$(mainv smtpd_milter_maps)"
expect 'InternalHosts loopback file' /var/opendkim/InternalHosts "$(key InternalHosts)"
expect 'milter_default_action untouched' accept "$(pce -h milter_default_action)"
row S2; pce -e 'smtpd_sasl_auth_enable = yes'; twice; case_is A
row S3; smtps; twice; case_is A

## no Lua (case D, decision 013)
nolua
row S4; twice; case_is D; state "$HOSTTABLE no"; ordered
expect 'main.cf macros = M' "$M" "$(mainv milter_mail_macros)"
expect 'main.cf smtpd_milter_maps = srvctl map' "cidr:$DIR/srvctl-milter-map" "$(mainv smtpd_milter_maps)"
expect 'map: 127.0.0.1 DISABLE' DISABLE "$(postmap -q 127.0.0.1 "cidr:$DIR/srvctl-milter-map" 2> /dev/null)"
expect 'map: ::1 DISABLE' DISABLE "$(postmap -q ::1 "cidr:$DIR/srvctl-milter-map" 2> /dev/null)"
expect 'map: container IP not listed' '' "$(postmap -q 10.20.1.5 "cidr:$DIR/srvctl-milter-map" 2> /dev/null)"
pickup_signs
expect_grep 'decision-013 err' 'built without Lua' "$tmp/errors"
row S5; pce -e 'smtpd_sasl_auth_enable = yes'; twice; case_is D; state "$HOSTTABLE no"
expect_grep 'decision-013 err' 'SMTP AUTH mail is not signed' "$tmp/errors"
row S6; smtps; pce -P 'smtps/inet/milter_mail_macros=i,{auth_type},{auth_authen},{mail_addr}' 'smtps/inet/smtpd_milter_maps=static:x'
twice; case_is D; ordered
expect 'smtps macro override removed' unset "$(ovr smtps/inet/milter_mail_macros)"
expect 'smtps milter map override removed' unset "$(ovr smtps/inet/smtpd_milter_maps)"
expect_grep 'removals reported' 'postconf -PX smtps/inet/milter_mail_macros' "$tmp/messages"

## no Lua -> Lua: srvctl's own values go back
lua
from S6 S7; twice; case_is A; ordered; state 'refile:/var/opendkim/EmptySigningTable yes'
expect 'M removed' '' "$(mainv milter_mail_macros)"
expect 'map setting removed' '' "$(mainv smtpd_milter_maps)"

## Lua but the login is hidden everywhere: case B (nolua), operator values kept
row S8; pce -e 'milter_mail_macros = i'; twice; case_is B; ordered; state "$HOSTTABLE no"
expect 'operator macros kept' i "$(mainv milter_mail_macros)"
expect 'map set' "cidr:$DIR/srvctl-milter-map" "$(mainv smtpd_milter_maps)"
expect_grep 'B err names the setting' "smtp/inet milter_mail_macros 'i'" "$tmp/errors"
row S9; smtps; pce -P 'smtps/inet/milter_mail_macros=i'; twice; case_is B
expect 'operator override kept' set:i "$(ovr smtps/inet/milter_mail_macros)"

## Lua, AUTH macros without the login: local-only (C-isolate)
row S10; smtps; pce -P 'smtps/inet/milter_mail_macros=i,{auth_type},{mail_addr}'
twice; case_is C-isolate; ordered; state "$HOSTTABLE no"; pickup_signs
expect 'smtp isolated' set: "$(ovr smtp/inet/smtpd_milters)"
expect 'smtps isolated' set: "$(ovr smtps/inet/smtpd_milters)"
expect 'isolation recorded' 'smtp/inet smtps/inet' "$(tr '\n' ' ' < "$DIR/srvctl-isolated-listeners" | sed 's/ $//')"
expect '10025 not recorded' 0 "$(grep -c 10025 "$DIR/srvctl-isolated-listeners")"
expect 'main.cf milters untouched' 'inet:127.0.0.1:8891' "$(pce -h smtpd_milters)"
expect_grep 'err names the hiding setting' 'smtps/inet milter_mail_macros' "$tmp/errors"
row S11; pce -e 'milter_mail_macros = i {auth_type} {mail_addr}'; twice; case_is C-isolate
expect 'operator v unchanged' 'i {auth_type} {mail_addr}' "$(mainv milter_mail_macros)"
from S10 S11b; pce -PX smtps/inet/milter_mail_macros; twice; case_is A; ordered
expect 'isolation undone' unset "$(ovr smtp/inet/smtpd_milters)"
expect 'record gone' no "$([[ -e $DIR/srvctl-isolated-listeners ]] && echo yes || echo no)"
expect '10025 override stays' set: "$(ovr 127.0.0.1:10025/inet/smtpd_milters)"
from S10 S11c; pce -e 'smtpd_milter_maps = cidr:/etc/postfix/other'
before="$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
twice; case_is C-conflict; state "$QUIET"
expect 'H1: Postfix untouched' "$before" "$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
expect_grep 'H1 err names the map' "main.cf smtpd_milter_maps 'cidr:/etc/postfix/other'" "$tmp/errors"

## no Lua, operator v = the built-in default: overwritten with M; then Lua
nolua
row S12; pce -e "milter_mail_macros = $(postconf -d -h milter_mail_macros)"; twice; case_is D
expect 'operator v -> M' "$M" "$(mainv milter_mail_macros)"
lua; from S12 S12b; twice; case_is A; expect 'M removed again' '' "$(mainv milter_mail_macros)"
nolua; from S1 S13; pce -e 'smtpd_sasl_auth_enable = yes'; twice; case_is D; ordered
expect 'first opendkim restart is to quiet' "opendkim-restart $QUIET" "$(head -n 1 "$LOG")"
## risky keys
row S15; printf 'Domain example.net\nKeyFile /x\nMacroList daemon_name|MSA\nMTA MSA\nSenderMacro auth_authen\n' >> "$CONF"
twice; expect 'risky keys removed' '' "$(grep -Ei '^(Domain|KeyFile|MacroList|MTA|SenderMacro)[[:space:]]' "$CONF")"
expect_grep 'removal reported' 'removed MacroList' "$tmp/messages"

## ---------------------------------------------------------------------------
## AC4a: parameter references in the routing decision
lua
row S16; smtps; pce -e 'my_dkim_milter = inet:127.0.0.1:8891'
pce -P 'smtps/inet/smtpd_milters=$my_dkim_milter' 'smtps/inet/milter_mail_macros=i,{auth_type},{mail_addr}'
before="$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
twice; case_is C-conflict; state "$QUIET"
expect 'Postfix untouched' "$before" "$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
expect_grep 'err names the reaching override' 'smtps/inet smtpd_milters .* reaches opendkim' "$tmp/errors"
row S17; smtps; pce -e 'my_dkim_milter = inet:127.0.0.1:8891' 'my_chain = $my_dkim_milter'
pce -P 'smtps/inet/smtpd_milters=$my_chain' 'smtps/inet/milter_mail_macros=i,{auth_type},{mail_addr}'
twice; case_is C-conflict
row S18; smtps; pce -P 'smtps/inet/smtpd_milters=$undefined_thing' 'smtps/inet/milter_mail_macros=i,{auth_type},{mail_addr}'
twice; case_is C-conflict; expect_grep 'err: cannot be resolved' 'cannot be resolved (undefined parameter $undefined_thing' "$tmp/errors"
row S19; smtps; pce -e 'other = inet:127.0.0.1:9999'
pce -P 'smtps/inet/smtpd_milters=$other' 'smtps/inet/milter_mail_macros=i,{auth_type},{mail_addr}'
twice; case_is C-isolate
expect 'operator override kept' 'set:$other' "$(ovr smtps/inet/smtpd_milters)"
expect 'only smtp recorded' smtp/inet "$(cat "$DIR/srvctl-isolated-listeners")"
row S20a; pce -e 'milter_mail_macros = $my_macros'; twice; case_is C-isolate
row S20b; pce -e 'milter_mail_macros = $my_macros' 'my_macros = i {auth_type} {auth_authen} {mail_addr}'; twice; case_is A

## AC4b: a recorded override is srvctl's only while it is still empty
from S10 S21; pce -P 'smtps/inet/smtpd_milters=inet:127.0.0.1:8891'
twice; case_is C-conflict; state "$QUIET"
expect 'stale entry dropped' smtp/inet "$(cat "$DIR/srvctl-isolated-listeners")"
expect 'operator value kept' set:inet:127.0.0.1:8891 "$(ovr smtps/inet/smtpd_milters)"
from S10 S22; pce -e 'my_dkim_milter = inet:127.0.0.1:8891'; pce -P 'smtps/inet/smtpd_milters=$my_dkim_milter'
twice; case_is C-conflict
from S10 S24; pce -PX smtps/inet/smtpd_milters
twice; case_is C-isolate
expect 'override written again' set: "$(ovr smtps/inet/smtpd_milters)"
expect 'and recorded again' 'smtp/inet smtps/inet' "$(tr '\n' ' ' < "$DIR/srvctl-isolated-listeners" | sed 's/ $//')"

## postscreen: smtpd runs as a pass service
row S23; smtps; pce -P 'smtps/inet/milter_mail_macros=i,{auth_type},{mail_addr}'
pce -M 'smtp/inet=smtp inet n - n - 1 postscreen' 'smtpd/pass=smtpd pass - - n - - smtpd'
twice; case_is C-isolate
expect 'pass service isolated and recorded' set:/1 "$(ovr smtpd/pass/smtpd_milters)/$(grep -cx smtpd/pass "$DIR/srvctl-isolated-listeners")"

## report-030 counterexamples
row S25; pce -e 'my_chain = inet:127.0.0.1:9999'
pce -P 'smtp/inet/my_chain=$undefined_thing' 'smtp/inet/smtpd_milters=$my_chain' 'smtp/inet/milter_mail_macros=i,{auth_type},{mail_addr}'
twice; case_is C-conflict; expect_grep 'err names the undefined name' 'undefined parameter $undefined_thing in smtp/inet' "$tmp/errors"
row S25b; pce -e 'my_chain = inet:127.0.0.1:9999'; pce -P 'smtp/inet/my_chain=$undefined_thing' 'smtp/inet/smtpd_milters=$my_chain'
twice; case_is A
row S26; pce -e 'my_macros = i {auth_type} {auth_authen} {mail_addr}' 'milter_mail_macros = $my_macros'
pce -P 'smtp/inet/my_macros=i,{auth_type}'
twice; case_is C-isolate; ordered; state "$HOSTTABLE no"
expect 'operator macros untouched' '$my_macros' "$(mainv milter_mail_macros)"
nolua; from S26 S26b; pce -PX smtp/inet/smtpd_milters; rm -f "$DIR/srvctl-isolated-listeners"
twice; case_is D; expect 'operator v -> M' "$M" "$(mainv milter_mail_macros)"
lua; row S27; pce -e 'my_macros = i {auth_type} {auth_authen} {mail_addr}' 'milter_mail_macros = $my_macros' 'my_chain = inet:127.0.0.1:8891'
pce -P 'smtp/inet/my_macros=i,{auth_type}' 'smtp/inet/smtpd_milters=$my_chain'
twice; case_is C-conflict

## unreadable configuration (a $reference cycle): Z, nothing edited
for l in lua nolua
do
    $l
    row "S28-$l"; pce -e 'a = $b' 'b = $a'; pce -P 'smtp/inet/smtpd_milters=$a'
    before="$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
    twice; case_is Z; state "$QUIET"
    expect 'no Postfix edit' "$before" "$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
    expect_grep 'err with the postconf error' 'cannot be read' "$tmp/errors"
done

## ---------------------------------------------------------------------------
## case D checks its own edits (report 033)
nolua
d033() { pce -e 'milter_mail_macros = i {auth_type} {mail_addr}' 'smtpd_sasl_auth_enable = yes'; pce -P 'smtp/inet/milter_mail_macros=i,{auth_type}'; }
row S29; d033; twice; case_is D; ordered; state "$HOSTTABLE no"
expect 'smtp override removed' unset "$(ovr smtp/inet/milter_mail_macros)"
expect 'exposed operator v -> M' "$M" "$(mainv milter_mail_macros)"
opendkim_pf_load "$DIR"; opendkim_pf_eval smtp/inet milter_mail_macros
expect 'smtp/inet sees no AUTH macro (resolver)' "ok $M" "$OPENDKIM_PF_STATE $OPENDKIM_PF_VALUE"
expect 'smtp/inet sees no AUTH macro (postconf -xh)' "$M" "$(pce -xh milter_mail_macros)"
row S29b; d033; smtps; pce -P 'smtps/inet/milter_mail_macros=i,{mail_addr}'; twice; case_is D
expect 'safe smtps override kept' 'set:i,{mail_addr}' "$(ovr smtps/inet/milter_mail_macros)"
expect 'unsafe smtp override removed' unset "$(ovr smtp/inet/milter_mail_macros)"
row S29c; d033
eval "real_neutral_check() $(declare -f opendkim_neutral_check | tail -n +2)"
opendkim_neutral_check() { OPENDKIM_UNSAFE=' smtp/inet forced'; return 1; }
before="$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
go 1; ROW=S29c; expect 'case' D-unsafe "$OPENDKIM_CASE"; state "$QUIET"
expect 'live Postfix untouched' "$before" "$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
expect_grep 'err names the service' 'smtp/inet forced' "$tmp/errors"
eval "opendkim_neutral_check() $(declare -f real_neutral_check | tail -n +2)"

## pickup-only layout: no smtpd service is valid, pickup stays signed
row S30; pce -MX smtp/inet 127.0.0.1:10025/inet; twice; case_is D; state "$HOSTTABLE no"; pickup_signs
expect 'map set' "cidr:$DIR/srvctl-milter-map" "$(mainv smtpd_milter_maps)"
lua; row S31; pce -MX smtp/inet 127.0.0.1:10025/inet; twice; case_is A; state 'refile:/var/opendkim/EmptySigningTable yes'; pickup_signs

## ---------------------------------------------------------------------------
## failed or skipped postfix restart (report 036)
nolua
row S32; d033; PF_RC=1; go 1
expect 'case' D "$OPENDKIM_CASE"; state "$QUIET"
expect 'run 1 log' "opendkim-restart-none|postfix-restart" "$(grep -q '^opendkim-restart' "$LOG" && echo has || echo opendkim-restart-none)|$(cut -d' ' -f1 "$LOG" | tr '\n' ' ' | sed 's/ $//')"
expect 'edits are live' "$M" "$(mainv milter_mail_macros)"
expect 'pending marker' yes "$([[ -e $DIR/srvctl-postfix-restart-pending ]] && echo yes || echo no)"
expect_grep 'err' 'postfix restart failed' "$tmp/errors"
cp -a "$tmp/S32" "$tmp/S32b-base"
PF_RC=0; edits="$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"; go 2
expect 'run 2: no Postfix edit' "$edits" "$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
expect 'run 2: marker forces the restart, then signing' "postfix-restart|opendkim-restart $HOSTTABLE no" "$(cut -d' ' -f1 "$LOG" | head -n 1)|$(grep '^opendkim-restart' "$LOG")"
expect 'marker removed' no "$([[ -e $DIR/srvctl-postfix-restart-pending ]] && echo yes || echo no)"
s3="$(sum)"; go 3
expect 'run 3: no restart' '' "$(cat "$LOG")"; expect 'run 3: same files' "$s3" "$(sum)"
from S32b-base S32b; PF_RC=1; edits="$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"; go 2
expect 'still failing: no Postfix edit' "$edits" "$(cat "$DIR/main.cf" "$DIR/master.cf" | sha256sum)"
expect 'restart retried' postfix-restart "$(cut -d' ' -f1 "$LOG")"
state "$QUIET"
expect 'marker kept' yes "$([[ -e $DIR/srvctl-postfix-restart-pending ]] && echo yes || echo no)"
lua; row S33; smtps; pce -P 'smtps/inet/milter_mail_macros=i,{auth_type},{mail_addr}'; PF_RC=1; go 1
state "$QUIET"; expect 'ISO written with the edits' 'smtp/inet smtps/inet' "$(tr '\n' ' ' < "$DIR/srvctl-isolated-listeners" | sed 's/ $//')"
PF_RC=0; go 2; expect 'case' C-isolate "$OPENDKIM_CASE"; ordered; state "$HOSTTABLE no"
nolua; row S34; d033
eval "opendkim_restart_postfix() $(declare -f real_restart_postfix | tail -n +2)"
systemctl() { echo "systemctl $*" >> "$LOG"; [[ $* != 'is-active --quiet postfix.service' ]]; }
go 1; expect 'case' D "$OPENDKIM_CASE"; state "$HOSTTABLE no"
expect 'postfix not running: not restarted' '' "$(grep 'systemctl restart' "$LOG")"
expect 'marker removed' no "$([[ -e $DIR/srvctl-postfix-restart-pending ]] && echo yes || echo no)"
s1="$(sum)"; go 2; expect 'run 2: same files' "$s1" "$(sum)"
expect 'run 2: no restart' '' "$(grep -v '^systemctl is-active' "$LOG")"

if (( failed ))
then
    echo 'Some opendkim conf tests FAILED.'
    exit 1
fi
echo 'All opendkim conf tests passed.'
