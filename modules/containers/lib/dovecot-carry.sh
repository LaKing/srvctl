#!/bin/bash

## Runs INSIDE a container, prepended to the script that calls these two:
##   upgrade-ve  lib/upgrade-ve-dnf.sh in the throwaway nspawn, around every distro-sync step
##   rebuild-ve  save in lib/rebuild-ve-backup.sh (old tree), carry in lib/rebuild-ve-restore.sh
##               (new tree); both through rebuild_ssh ... bash -s (libs/rebuildlib.sh)
##
## Dovecot 2.4 (Fedora 42 on) reads none of the 2.3 configuration. The package drops the
## conf.d files (a changed one stays as .rpmsave), and its stock dovecot.conf reads ~/mail,
## serves no POP3 and separates folders with /. So after the upgrade dovecot either does not
## start or serves empty mailboxes while postfix keeps delivering to ~/Maildir (seen on p2:
## mail.printhub.hu). The 2.3 settings are saved while 2.3 is installed and carried into
## conf.d/90-srvctl-dovecot23.conf once 2.4 is; what has no safe 2.4 equivalent is named,
## not guessed.

## the 2.3 settings, doveconf -n plus the values -n leaves out as defaults
function dovecot_save_23() { ## dovecot-dir
    local dc="$1"
    [[ $(rpm -q --qf '%{VERSION}' dovecot 2> /dev/null) == 2.3.* && ! -f $dc/doveconf-2.3.txt ]] || return 0
    doveconf -n > /dev/null 2>&1 || { echo "== NOTE: the dovecot 2.3 configuration does not parse, nothing saved to carry"; return 0; }
    {
        echo "# protocols = $(doveconf -h protocols)"
        echo "# ssl_key = $(doveconf -h ssl_key)"
        echo "# home_mailbox = $(postconf -h home_mailbox 2> /dev/null)"
        doveconf -n
    } > "$dc/doveconf-2.3.txt"
    echo "== dovecot 2.3 settings saved to $dc/doveconf-2.3.txt"
}

## once 2.4 is in, the stock configuration plus the carried settings
function dovecot_carry_24() { ## dovecot-dir home-dir
    local dc="$1" home="$2" old="$1/doveconf-2.3.txt" out="$1/conf.d/90-srvctl-dovecot23.conf" f maildir=
    [[ -f $old && ! -f $out && $(rpm -q --qf '%{VERSION}' dovecot 2> /dev/null) == 2.4.* ]] || return 0
    ## a changed 2.3 dovecot.conf stays and the 2.4 one lands beside it; a conf.d file left
    ## now is hand made or an .rpmsave, its settings are in the saved doveconf -n
    [[ -f $dc/dovecot.conf.rpmnew ]] && mv "$dc/dovecot.conf" "$dc/dovecot.conf.srvctl-2.3" && mv "$dc/dovecot.conf.rpmnew" "$dc/dovecot.conf"
    for f in "$dc"/conf.d/*.conf
    do
        [[ -f $f ]] && mv "$f" "$f.srvctl-2.3" && echo "== dovecot: $f set aside as .srvctl-2.3"
    done
    ## an empty 2.3 mail_location autodetected ~/Maildir, where postfix delivers
    grep -qx '# home_mailbox = Maildir/' "$old" && maildir=1
    compgen -G "$home/*/Maildir" > /dev/null && maildir=1
    mkdir -p "$dc/conf.d"
    awk -v maildir="$maildir" -f <(dovecot_carry_awk) "$old" > "$out"
    if doveconf -n > /dev/null
    then echo "== dovecot 2.4: the 2.3 settings carried in $out"
    else echo "== NOTE: dovecot 2.4 does not accept $out; dovecot will not start until it is fixed by hand"
    fi
}

## doveconf -n of 2.3 -> 2.4 drop-in. Top level blocks end with a "}" in column 0.
## service and protocol blocks are the same syntax in 2.4; passdb/userdb are carried only
## as the stock pam/passwd; the rest is listed as not carried (on stderr, and in the file).
function dovecot_carry_awk() {
    cat << 'AWK'
BEGIN { print "## srvctl: the Dovecot 2.3 settings of this container (/etc/dovecot/doveconf-2.3.txt)"; keep["ssl"]; keep["ssl_cipher_list"]; keep["ssl_min_protocol"]; keep["first_valid_uid"]; keep["last_valid_uid"]; keep["auth_mechanisms"]; keep["mail_privileged_group"]; skip["mbox_write_locks"]; skip["ssl_cert"]; skip["ssl_key"]; skip["mail_location"] }
function note(s) { notes = notes "# not carried: " s "\n"; print "== NOTE: dovecot 2.3 setting not carried: " s > "/dev/stderr" }
/^# protocols = / { n = split(substr($0, 15), p, " "); for (i = 1; i <= n; i++) prot = prot "  " p[i] " = yes\n"; next }
/^# ssl_key = </ { key = substr($0, 14); next }
/^#/ { next }
block != "" { body = body $0 "\n"; if ($0 == "}") { flush(); block = "" } ; next }
/ \{$/ { block = $0; body = $0 "\n"; next }
/ = / { k = $1; v = substr($0, index($0, " = ") + 3); if (k == "mail_location") loc = v; else if (k == "ssl_cert") cert = v; else if (k in keep) print k " = " v; else if (!(k in skip)) note($0); next }
function flush() {
    if (block ~ /^(service|protocol) /) { printf "%s", body; return }
    if (block == "namespace inbox {") { ns = body; return }
    if ((block == "passdb {" && body ~ /driver = pam\n/) || (block == "userdb {" && body ~ /driver = passwd\n/)) return
    note(block " ... }")
}
END {
    if (prot != "") printf "protocols {\n%s}\n", prot
    md = 1
    if (loc ~ /^maildir:/) { split(substr(loc, 9), l, ":"); print "mail_path = " l[1] }
    else if (loc == "" && maildir) print "mail_path = ~/Maildir"
    else { md = 0; if (loc != "") note("mail_location = " loc) }
    if (cert != "" && cert != "</etc/pki/dovecot/certs/dovecot.pem") printf "ssl_server {\n  cert_file = %s\n  key_file = %s\n}\n", substr(cert, 2), key
    ## 2.3 separated maildir++ folders with "."; 2.4's stock "/" would rename them for the clients
    if (ns == "") ns = "namespace inbox {\n}\n"
    if (md && ns !~ /\n  separator = /) sub(/\{\n/, "{\n  separator = .\n", ns)
    gsub(/\n  location = ?\n/, "\n", ns)
    if (ns != "namespace inbox {\n}\n") printf "%s", ns
    printf "%s", notes
}
AWK
}
