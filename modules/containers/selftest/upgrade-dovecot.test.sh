#!/bin/bash
# lib/upgrade-ve-dovecot.sh with rpm, doveconf and postconf stubbed: the 2.3 settings saved
# once, carried once into the 2.4 drop-in, files set aside, what is not carried named.
# The drop-in against a real 2.4 doveconf was checked on p2 (mail.printhub.hu's settings).
# shellcheck disable=SC2329

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

dc="$tmp/dovecot" home="$tmp/home"
rpm() { cat "$tmp/version"; }
postconf() { echo Maildir/; }
doveconf() {
    case "$1" in
        -h) case "$2" in protocols) echo imap pop3 lmtp ;; ssl_key) echo '</k.pem' ;; esac ;;
        -n) [[ $(cat "$tmp/version") == 2.3.* ]] && cat "$tmp/n" || ! grep -q broken "$dc"/conf.d/*.conf ;;
    esac
}
# shellcheck source=/dev/null
source "$REPO/modules/containers/lib/upgrade-ve-dovecot.sh"

fresh() {
    rm -rf "$dc" "$home" && mkdir -p "$dc/conf.d" "$home"
    echo 2.3.21 > "$tmp/version"
    cat > "$tmp/n" << 'EOF'
# 2.3.21: /etc/dovecot/dovecot.conf
mbox_write_locks = fcntl
namespace inbox {
  inbox = yes
  location =
  mailbox Sent {
    special_use = \Sent
  }
  prefix =
}
passdb {
  driver = pam
}
service imap-login {
  inet_listener imaps2 {
    port = 2993
    ssl = yes
  }
}
ssl = required
ssl_cert = </etc/pki/dovecot/certs/dovecot.pem
userdb {
  driver = passwd
}
protocol imap {
  mail_max_userip_connections = 30
}
EOF
}
names() { find "$1" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' '; }
drop() { cat "$dc/conf.d/90-srvctl-upgrade.conf" 2> /dev/null; }

## saved on 2.3 only, and once
fresh
upgrade_dovecot_save "$dc" > /dev/null
ok "saved" "$(head -n 3 "$dc/doveconf-2.3.txt" | tr '\n' '|')" "# protocols = imap pop3 lmtp|# ssl_key = </k.pem|# home_mailbox = Maildir/|"
echo changed > "$tmp/n"
upgrade_dovecot_save "$dc" > /dev/null
ok "saved once" "$(grep -c mbox_write_locks "$dc/doveconf-2.3.txt")" 1
upgrade_dovecot_carry "$dc" "$home" > /dev/null
ok "nothing carried while 2.3" "$(drop)" ""

## carried after 2.4 came in
echo 2.4.5 > "$tmp/version"
echo 'protocols = imap' > "$dc/conf.d/10-mine.conf"
touch "$dc/dovecot.conf" "$dc/dovecot.conf.rpmnew"
out="$(upgrade_dovecot_carry "$dc" "$home" 2>&1)"
ok "accepted" "$(grep -c 'settings carried' <<< "$out")" 1
ok "conf.d file set aside" "$(names "$dc/conf.d")" "10-mine.conf.srvctl-2.3 90-srvctl-upgrade.conf "
ok "2.4 dovecot.conf in place" "$(names "$dc")" "conf.d doveconf-2.3.txt dovecot.conf dovecot.conf.srvctl-2.3 "
ok "protocols" "$(drop | sed -n '/^protocols {/,/^}/p' | tr -d ' \n')" "protocols{imap=yespop3=yeslmtp=yes}"
ok "Maildir" "$(drop | grep -c '^mail_path = ~/Maildir$')" 1
ok "listener" "$(drop | grep -c 'inet_listener imaps2 {')" 1
ok "protocol block" "$(drop | grep -c 'mail_max_userip_connections = 30')" 1
ok "kept setting" "$(drop | grep -c '^ssl = required$')" 1
ok "default cert not repeated" "$(drop | grep -c ssl_server)" 0
ok "separator of 2.3" "$(drop | sed -n '/^namespace inbox {/{n;p}')" "  separator = ."
ok "empty location dropped" "$(drop | grep -c location)" 0
ok "stock passdb/userdb not repeated" "$(drop | grep -cE 'passdb|userdb|driver')" 0
ok "no notes" "$(grep -c 'not carried' <<< "$out")" 0
ok "carried once" "$(upgrade_dovecot_carry "$dc" "$home"; drop | grep -c imaps2)" 1

## what has no safe 2.4 equivalent is named; a cert of its own goes to ssl_server
fresh
sed -i -e 's/driver = pam/driver = sql/' -e 's#^ssl_cert = .*#ssl_cert = </c.pem\nmail_location = mdbox:~/mdbox\ndisable_plaintext_auth = no#' "$tmp/n"
upgrade_dovecot_save "$dc" > /dev/null
echo 2.4.5 > "$tmp/version"
out="$(upgrade_dovecot_carry "$dc" "$home" 2>&1)"
ok "notes" "$(grep -o 'not carried: .*' <<< "$out" | tr '\n' '|')" "not carried: passdb { ... }|not carried: disable_plaintext_auth = no|not carried: mail_location = mdbox:~/mdbox|"
ok "notes in the file" "$(drop | grep -c '^# not carried')" 3
ok "own cert" "$(drop | sed -n '/^ssl_server {/,/^}/p' | tr -d ' \n')" "ssl_server{cert_file=/c.pemkey_file=/k.pem}"
ok "no separator for mdbox" "$(drop | grep -c separator)" 0

## a drop-in 2.4 refuses is reported and left for the hand
fresh
upgrade_dovecot_save "$dc" > /dev/null
echo 2.4.5 > "$tmp/version"
echo 'broken = yes' >> "$dc/doveconf-2.3.txt"
out="$(upgrade_dovecot_carry "$dc" "$home" 2>&1)"
ok "refused named" "$(grep -c 'does not accept' <<< "$out")" 1

echo "upgrade-dovecot: $pass passed, $fail failed"
((fail == 0))
