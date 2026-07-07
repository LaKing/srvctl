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
get() { case "$*" in *" exist") echo true;; *" user") echo "$OWNER";; *" reseller") echo "$RESELLER";; *" role") echo "${ROLE_FIELD:-}";; *) echo "";; esac; return "${GET_RC:-0}"; }
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
      SC_USER="$2" SC_UID0="$3" USER="$2" GET_RC="${GET_RC:-0}" ROLE_FIELD="${ROLE_FIELD:-}" \
      SC_ROLE="${PRESET_SC_ROLE:-}"
    # real guards (owner_only/root_only) with their deps (get/sudomize/err)
    # stubbed by STUBS, which is sourced AFTER so its stubs win.
    # shellcheck disable=SC1090,SC1091
    source "$REPO/modules/srvctl/libs/authlib.sh"
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
CMDS_recreate="source $REPO/modules/containers/commands/recreate-ve.sh"
CMDS_mapport="source $REPO/modules/containers/commands/map-port.sh"
CMDS_backupcmd="source $REPO/modules/containers/commands/backup-ve.sh"
CMDS_backup="source $REPO/modules/containers/libs/backupcontainerlib.sh; backup_ve site.example.com"

# All eight owner commands now share owner_only.
OWNER_CMDS=(
  "destroy-ve:$CMDS_destroyve" "remove-ve:$CMDS_removeve" "http-redirect:$CMDS_httpredir"
  "override-in-address:$CMDS_override" "https-redirect:$CMDS_httpsredir"
  "recreate-ve:$CMDS_recreate" "map-port:$CMDS_mapport" "backup-ve:$CMDS_backupcmd"
)
for pair in "${OWNER_CMDS[@]}"; do
  name="${pair%%:*}"; snippet="${pair#*:}"
  probe "$snippet" mallory false      # non-owner, non-root
  ok "$name: non-owner DENIED (exit 44)" "$RC" "44"
  ok "$name: non-owner ran NO action"    "$(has_action "$MARKS")" "no"   # check-before-act
  probe "$snippet" alice false         # owner, non-root
  ok "$name: owner ESCALATES (sudomize)" "$([[ ",$MARKS," == *",sudomize,"* ]] && echo yes || echo no)" "yes"
done

# WP-E.2 owner_only: root may act on everything for everyone, even a container
# it does not own. (backup-ve excluded: its action's `out > /srv/$C/...`
# redirect fails before the stub records, so has_action is unreliable there.)
for pair in "destroy-ve:$CMDS_destroyve" "remove-ve:$CMDS_removeve" "http-redirect:$CMDS_httpredir" "override-in-address:$CMDS_override" "https-redirect:$CMDS_httpsredir" "recreate-ve:$CMDS_recreate" "map-port:$CMDS_mapport"; do
  name="${pair%%:*}"; snippet="${pair#*:}"
  probe "$snippet" mallory true        # root, but NOT the owner
  ok "$name: root (non-owner) ALLOWED" "$(has_action "$MARKS")" "yes"
done

# owner_only lookup-error propagation: a DATASTORE ERROR from `get` (exit != 0
# and != 100) must NOT be reported as a "no access" 44 denial — it must
# propagate the datastore/lookup failure. (get 112 = LIB-ERROR.)
GET_RC=112 probe "$CMDS_mapport" mallory false
ok "owner_only: datastore error propagates (not 44)"  "$RC" "112"
ok "owner_only: datastore error ran NO action"        "$(has_action "$MARKS")" "no"
# a legitimate 'optional absent' (100) on the reseller field is NOT an error:
# with no owner match it is still a normal 44 denial.
GET_RC=100 probe "$CMDS_mapport" mallory false
ok "owner_only: 100 (optional absent) still a clean 44 deny" "$RC" "44"

# backup_ve: the owner-check is in its CALLER; the lib gate itself just needs
# non-root to be denied.
probe "$CMDS_backup" mallory false
ok "backup_ve: non-root DENIED (exit 44)" "$RC" "44"
ok "backup_ve: non-root ran NO action"    "$(has_action "$MARKS")" "no"

echo "== (B) raw verb dispatch (non-root): writes blocked, reads open =="
verbcheck() { # $1 CMD  -> echoes verbs run_command invoked
  local mf; mf="$(mktemp)"
  (
    set +u
    export MARKFILE="$mf" SRVCTL=1   # commonlib.sh guards on [[ $SRVCTL ]]
    # shellcheck disable=SC1090,SC1091
    source "$REPO/commonlib.sh"
    # override verb wrappers + fall-through helpers AFTER sourcing commonlib
    for v in new put cfg del add get out; do eval "$v() { echo $v >> \"\$MARKFILE\"; }"; done
    exif() { :; } ; err() { :; } ; hint() { :; } ; complicate() { :; } ; title() { :; }
    msg() { :; } ; ntc() { :; } ; prg() { :; } ; debug() { :; }
    # ShellCheck cannot see these are consumed by run_command from commonlib.sh.
    # shellcheck disable=SC2034
    CMD="$1"
    # shellcheck disable=SC2034
    OPAS="container site.example.com x"
    ARG="site.example.com"
    # shellcheck disable=SC2034
    SC_MODULES=""
    # shellcheck disable=SC2034
    SC_HOME="/nonexistent-$$"
    run_command
  ) > /dev/null 2>&1
  paste -sd, "$mf" 2> /dev/null
  command rm -f "$mf"
}
for v in new put cfg del add; do ok "non-root raw '$v' BLOCKED" "$(verbcheck "$v")" ""; done
for v in get out; do ok "non-root raw '$v' allowed" "$(verbcheck "$v")" "$v"; done

echo "== (C) sudomize: faithful argv (SC_ARGV) + real exit status =="
ARGFILE=""
sudo_probe() { # $1 = setup snippet (sets SC_ARGV/SC_COMMAND_ARGUMENTS + FAKE_SUDO_RC)
  ARGFILE="$(mktemp)"
  (
    set +u
    export SRVCTL=1 SC_INSTALL_DIR="/opt/sc" SC_UID0=false ARGFILE_E="$ARGFILE"
    # shellcheck disable=SC1090,SC1091
    source "$REPO/modules/srvctl/libs/authlib.sh"   # real sudomize under test
    sudo() { local a; for a in "$@"; do echo "$a" >> "$ARGFILE_E"; done; return "${FAKE_SUDO_RC:-0}"; }
    debug() { :; }
    eval "$1"
    sudomize
  ) > /dev/null 2>&1
  RC=$?
}
# faithful argv: an argument containing spaces stays ONE argument (one line)
sudo_probe 'FAKE_SUDO_RC=0; SC_ARGV=(new container "site with space" fedora)'
ok "sudomize: passes srvctl.sh path"   "$(grep -Fxq '/opt/sc/srvctl.sh' "$ARGFILE" && echo yes || echo no)" "yes"
ok "sudomize: preserves spaced arg"    "$(grep -Fxq 'site with space' "$ARGFILE" && echo yes || echo no)" "yes"
ok "sudomize: exit 0 on sudo success"  "$RC" "0"
command rm -f "$ARGFILE"
# real exit status propagates (was masked to 0)
sudo_probe 'FAKE_SUDO_RC=7; SC_ARGV=(version)'
ok "sudomize: propagates sudo status"  "$RC" "7"
command rm -f "$ARGFILE"
# fallback path (no SC_ARGV) still re-execs
sudo_probe 'FAKE_SUDO_RC=0; SC_COMMAND_ARGUMENTS="version"'
ok "sudomize: fallback re-execs"       "$(grep -Fq 'version' "$ARGFILE" && echo yes || echo no)" "yes"
command rm -f "$ARGFILE"

echo "== (D) role x class ENFORCEMENT matrix (WP-E.2.b) =="
FXD="$REPO/modules/srvctl/selftest/authfixtures"
FX_every="source $FXD/everyone.sh"; FX_root="source $FXD/rootonly.sh"
FX_ops="source $FXD/operatorsonly.sh"; FX_owner="source $FXD/owneronly.sh"

# EVERYONE: every role runs it
probe "$FX_every" root true                              ; ok "root: everyone RUN"       "$(has_action "$MARKS")" "yes"
ROLE_FIELD=operator probe "$FX_every" op false           ; ok "operator: everyone RUN"   "$(has_action "$MARKS")" "yes"
probe "$FX_every" bob false                              ; ok "user: everyone RUN"       "$(has_action "$MARKS")" "yes"
# ROOT_ONLY: only root
probe "$FX_root" root true                               ; ok "root: root_only RUN"      "$(has_action "$MARKS")" "yes"
ROLE_FIELD=operator probe "$FX_root" op false            ; ok "operator: root_only DENY" "$RC" "44"
probe "$FX_root" bob false                               ; ok "user: root_only DENY"     "$RC" "44"
# OPERATORS_ONLY: root + operator
probe "$FX_ops" root true                                ; ok "root: operators_only RUN" "$(has_action "$MARKS")" "yes"
ROLE_FIELD=operator probe "$FX_ops" op false             ; ok "operator: operators_only RUN" "$(has_action "$MARKS")" "yes"
probe "$FX_ops" bob false                                ; ok "user: operators_only DENY"    "$RC" "44"
PRESET_SC_ROLE=operator probe "$FX_ops" bob false         ; ok "inherited SC_ROLE spoof DENY" "$RC" "44"
# OWNER_ONLY: root (any), owner escalates, non-owner denied — INCLUDING an
# operator who is not the owner (operators do NOT bypass ownership)
probe "$FX_owner" root true                              ; ok "root: owner_only(non-owner) RUN" "$(has_action "$MARKS")" "yes"
probe "$FX_owner" alice false                            ; ok "owner: owner_only ESCALATES"  "$([[ ",$MARKS," == *",sudomize,"* ]] && echo yes || echo no)" "yes"
ROLE_FIELD=operator probe "$FX_owner" op false           ; ok "operator(non-owner): owner_only DENY" "$RC" "44"
probe "$FX_owner" mallory false                          ; ok "user(non-owner): owner_only DENY"     "$RC" "44"

echo "== (E) role x class VISIBILITY (hint_on_file listing filter, WP-E.2.b) =="
shown() { [[ $1 == 0 ]] && echo shown || echo hidden; }   # hint_on_file: 0=render, 133/134=hidden
VISRC=0
vis() { # $1 fixture basename  $2 SC_USER  $3 SC_UID0
  (
    set +u
    export SRVCTL=1 SC_INSTALL_DIR="$REPO" SC_USER="$2" SC_UID0="$3" SC_HOSTNET=42 \
      OWNER=alice RESELLER=bob GET_RC=0 ROLE_FIELD="${ROLE_FIELD:-}" MARKFILE=/dev/null SC_ROLE=""
    # shellcheck disable=SC1090,SC1091
    source "$REPO/modules/srvctl/libs/authlib.sh"   # real sc_role
    # shellcheck disable=SC1090
    source "$STUBS"                                  # get returns ROLE_FIELD for 'role'
    # shellcheck disable=SC1090,SC1091
    source "$REPO/commonlib.sh"                      # real hint_on_file
    hint() { :; } ; complicate() { :; } ; title() { :; }
    # consumed by hint_on_file (sourced commonlib.sh); shellcheck can't see it
    # shellcheck disable=SC2034
    SC_IDX_BUILT=false                               # exercise the grep fallback filter
    hint_on_file "$REPO/modules/srvctl/selftest/authfixtures/$1.sh"
  ) > /dev/null 2>&1
  VISRC=$?
}
# everyone: visible to every role
vis everyone root true                 ; ok "root sees everyone"        "$(shown "$VISRC")" "shown"
ROLE_FIELD=operator vis everyone op false ; ok "operator sees everyone" "$(shown "$VISRC")" "shown"
vis everyone bob false                 ; ok "user sees everyone"        "$(shown "$VISRC")" "shown"
# root_only: only root
vis rootonly root true                 ; ok "root sees root_only"       "$(shown "$VISRC")" "shown"
ROLE_FIELD=operator vis rootonly op false ; ok "operator HIDDEN root_only" "$(shown "$VISRC")" "hidden"
vis rootonly bob false                 ; ok "user HIDDEN root_only"     "$(shown "$VISRC")" "hidden"
# operators_only: root + operator
vis operatorsonly root true            ; ok "root sees operators_only"  "$(shown "$VISRC")" "shown"
ROLE_FIELD=operator vis operatorsonly op false ; ok "operator sees operators_only" "$(shown "$VISRC")" "shown"
vis operatorsonly bob false            ; ok "user HIDDEN operators_only" "$(shown "$VISRC")" "hidden"
# owner_only: resource-scoped, always LISTED (enforced per-resource at run time)
vis owneronly root true                ; ok "root sees owner_only"      "$(shown "$VISRC")" "shown"
ROLE_FIELD=operator vis owneronly op false ; ok "operator sees owner_only" "$(shown "$VISRC")" "shown"
vis owneronly bob false                ; ok "user sees owner_only"      "$(shown "$VISRC")" "shown"

command rm -f "$STUBS"
echo ""
echo "authgate.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
