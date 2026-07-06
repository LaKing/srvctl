#!/bin/bash
#
# modules/srvctl/selftest/authgate.test.sh — WP-E.1 deny/allow probe.
#
# Focused behavioural test for the owner-gate + raw-verb-dispatch security
# fixes. Datastore verbs and destructive ops are STUBBED, so running this
# against the PRE-FIX tree is safe — it just fails (showing the bug).
#
#  (A) The five owner-gated commands. A NON-OWNER NON-ROOT caller must be
#      DENIED (exit 44); an OWNER must ESCALATE (sudomize).
#  (B) run_command's raw datastore-verb dispatch. A non-root caller must NOT
#      reach the WRITE verbs (new/put/cfg/del/add); READS (get/out) stay open.
#
# Must run as NON-ROOT (UID != 0) so SC_UID0=false and the $UID gate matter.
# Exit != 0 on any failure.

# Intentional patterns: probe subshells set env vars locally (isolation), and
# the verb/action stubs are invoked indirectly by the sourced commands.
# shellcheck disable=SC2030,SC2031,SC2329
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }
has_action() { local m=",$1,"; local a; for a in put out add del new cfg rm systemctl machinectl chroot rsync run run_hook regen; do [[ $m == *",$a,"* ]] && { echo yes; return; }; done; echo no; }

if [[ $UID == 0 ]]; then
  echo "SKIP authgate.test: must run as non-root (UID != 0) to exercise SC_UID0=false" >&2
  exit 0
fi

# stub definitions sourced into each probe subshell
STUBS="$(mktemp)"
cat > "$STUBS" << 'STUB'
mark() { echo "$1" >> "$MARKFILE"; }
get() { case "$*" in *" exist") echo true;; *" user") echo "$OWNER";; *" reseller") echo "$RESELLER";; *) echo "";; esac; }
put() { mark put; } ; out() { mark out; } ; add() { mark add; } ; del() { mark del; } ; new() { mark new; } ; cfg() { mark cfg; }
sudomize() { if ! $SC_UID0; then mark sudomize; exit 0; fi; }   # like the real one: only re-execs when non-root
argument() { :; } ; authorize() { :; } ; hs_only() { :; } ; ve_only() { :; }
msg() { :; } ; err() { mark err; } ; ntc() { :; } ; prg() { :; } ; debug() { :; } ; exif() { :; } ; eyif() { :; }
run() { mark run; } ; run_hook() { mark run_hook; }
regenerate_haproxy_conf() { mark regen; } ; regenerate_certificates() { mark regen; }
rm() { mark rm; } ; systemctl() { mark systemctl; } ; machinectl() { mark machinectl; }
chroot() { mark chroot; } ; rsync() { mark rsync; } ; umount() { :; } ; quotaoff() { :; } ; quotaon() { :; }
STUB

RC=0; MARKS=""
probe() { # $1 = shell snippet   $2 SC_USER   $3 SC_UID0
  local mf; mf="$(mktemp)"
  (
    set +u   # real srvctl commands reference optional vars unquoted; not nounset-safe
    export MARKFILE="$mf" SRVCTL=1 SC_INSTALL_DIR="$REPO" ARG="site.example.com" OPA="none" \
      C="site.example.com" NOW="x" HOSTNAME="testhost" OWNER="alice" RESELLER="bob" \
      SC_USER="$2" SC_UID0="$3" USER="$2"
    # shellcheck disable=SC1090
    source "$STUBS"
    eval "$1"
  ) > /dev/null 2>&1
  RC=$?
  MARKS="$(paste -sd, "$mf" 2> /dev/null)"
  command rm -f "$mf"
}

echo "== (A) owner-gated commands =="
CMDS_destroyve="source $REPO/modules/containers/commands/destroy-ve.sh"
CMDS_removeve="source $REPO/modules/containers/commands/remove-ve.sh"
CMDS_httpredir="source $REPO/modules/haproxy/commands/http-redirect.sh"
CMDS_override="source $REPO/modules/named/commands/override-in-address.sh"
CMDS_httpsredir="source $REPO/modules/haproxy/commands/https-redirect.sh"
CMDS_backup="source $REPO/modules/containers/libs/backupcontainerlib.sh; backup_ve site.example.com"

for pair in "destroy-ve:$CMDS_destroyve" "remove-ve:$CMDS_removeve" "http-redirect:$CMDS_httpredir" "override-in-address:$CMDS_override" "https-redirect:$CMDS_httpsredir"; do
  name="${pair%%:*}"; snippet="${pair#*:}"
  probe "$snippet" mallory false      # non-owner, non-root
  ok "$name: non-owner DENIED (exit 44)" "$RC" "44"
  ok "$name: non-owner ran NO action"    "$(has_action "$MARKS")" "no"
  probe "$snippet" alice false         # owner, non-root
  ok "$name: owner ESCALATES (sudomize)" "$([[ ",$MARKS," == *",sudomize,"* ]] && echo yes || echo no)" "yes"
done

# backup_ve: the owner-check is in its CALLER; the lib gate itself just needs
# non-root to be denied.
probe "$CMDS_backup" mallory false
ok "backup_ve: non-root DENIED (exit 44)" "$RC" "44"
ok "backup_ve: non-root ran NO action"    "$(has_action "$MARKS")" "no"

# map-port sudomizes UNCONDITIONALLY before the owner-check, so its real deny
# is in the post-escalation root-but-not-owner state (SC_UID0=true, SC_USER is
# the preserved non-owner).
MP="source $REPO/modules/containers/commands/map-port.sh"
probe "$MP" mallory true                 # root-but-not-owner
ok "map-port: non-owner (post-sudo) DENIED (exit 44)" "$RC" "44"
ok "map-port: non-owner ran NO action"               "$(has_action "$MARKS")" "no"
probe "$MP" alice true                    # owner (post-sudo)
ok "map-port: owner reaches action"                  "$(has_action "$MARKS")" "yes"

echo "== (B) raw verb dispatch (non-root): writes blocked, reads open =="
verbcheck() { # $1 CMD  -> echoes verbs run_command invoked
  local mf; mf="$(mktemp)"
  (
    set +u
    export MARKFILE="$mf" SRVCTL=1   # commonlib.sh guards on [[ $SRVCTL ]]
    # shellcheck disable=SC1090
    source "$REPO/commonlib.sh"
    # override verb wrappers + fall-through helpers AFTER sourcing commonlib
    for v in new put cfg del add get out; do eval "$v() { echo $v >> \"\$MARKFILE\"; }"; done
    exif() { :; } ; err() { :; } ; hint() { :; } ; complicate() { :; } ; title() { :; }
    msg() { :; } ; ntc() { :; } ; prg() { :; } ; debug() { :; }
    CMD="$1" ; OPAS="container site.example.com x" ; ARG="site.example.com"
    SC_MODULES="" ; SC_HOME="/nonexistent-$$"
    run_command
  ) > /dev/null 2>&1
  paste -sd, "$mf" 2> /dev/null
  command rm -f "$mf"
}
for v in new put cfg del add; do ok "non-root raw '$v' BLOCKED" "$(verbcheck "$v")" ""; done
for v in get out; do ok "non-root raw '$v' allowed" "$(verbcheck "$v")" "$v"; done

command rm -f "$STUBS"
echo ""
echo "authgate.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
