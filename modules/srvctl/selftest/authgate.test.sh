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
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }
has_action() { local m=",$1,"; local a; for a in put out add del new cfg rm systemctl machinectl chroot rsync run run_hook regen; do [[ $m == *",$a,"* ]] && { echo yes; return; }; done; echo no; }
has_mark() { [[ ",$1," == *",$2,"* ]] && echo yes || echo no; }

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
service_action() { mark service_action; } ; exit_0() { :; }
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

# GENUINE root (SC_USER=root + uid 0) may act on everything, even a container
# it does not own. But the SUDO BYPASS (WP-E.2.b audit) must be closed: a
# NON-owner who reaches uid 0 via `sudo srvctl.sh` keeps SC_USER=<them>, so
# they are NOT root and MUST be denied. (backup-ve excluded: its action's
# `out > /srv/$C/...` redirect fails before the stub records has_action.)
for pair in "destroy-ve:$CMDS_destroyve" "remove-ve:$CMDS_removeve" "http-redirect:$CMDS_httpredir" "override-in-address:$CMDS_override" "https-redirect:$CMDS_httpsredir" "recreate-ve:$CMDS_recreate" "map-port:$CMDS_mapport"; do
  name="${pair%%:*}"; snippet="${pair#*:}"
  probe "$snippet" root true           # genuine root, not the owner
  ok "$name: genuine-root (non-owner) ALLOWED" "$(has_action "$MARKS")" "yes"
  probe "$snippet" alice true          # owner in the post-sudomize uid 0 state
  ok "$name: owner (post-sudo uid0) ALLOWED" "$(has_action "$MARKS")" "yes"
  probe "$snippet" mallory true        # uid 0 via sudo, but SC_USER != root, not owner
  ok "$name: SUDO-BYPASS (uid0 non-root) DENIED" "$RC" "44"
  ok "$name: SUDO-BYPASS ran NO action"          "$(has_action "$MARKS")" "no"
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
probe "$FX_owner" alice true                             ; ok "owner(post-sudo uid0): owner_only RUN" "$(has_action "$MARKS")" "yes"
ROLE_FIELD=operator probe "$FX_owner" op false           ; ok "operator(non-owner): owner_only DENY" "$RC" "44"
probe "$FX_owner" mallory false                          ; ok "user(non-owner): owner_only DENY"     "$RC" "44"
# SUDO BYPASS across classes: a non-root user at uid 0 (SC_USER != root, no
# operator role) is still just a user — uid 0 alone must not grant anything.
probe "$FX_root" mallory true                            ; ok "sudo-bypass: root_only DENY"      "$RC" "44"
probe "$FX_ops" mallory true                             ; ok "sudo-bypass: operators_only DENY" "$RC" "44"
probe "$FX_owner" mallory true                           ; ok "sudo-bypass: owner_only DENY"     "$RC" "44"

echo "== (E) role x class VISIBILITY (hint_on_file listing filter, WP-E.2.b) =="
shown() { case "$1" in 0) echo shown;; 133|134) echo hidden;; *) echo "rc:$1";; esac; }   # hint_on_file: 0=render, 133/134=hidden
VISRC=0
vis() { # $1 fixture basename  $2 SC_USER  $3 SC_UID0  $4 grep|indexed
  local fixture user uid0 mode file
  fixture="$1"; user="$2"; uid0="$3"; mode="${4:-grep}"
  file="$REPO/modules/srvctl/selftest/authfixtures/$fixture.sh"
  (
    set +u
    export SRVCTL=1 SC_INSTALL_DIR="$REPO" SC_USER="$user" SC_UID0="$uid0" SC_HOSTNET=42 \
      OWNER=alice RESELLER=bob GET_RC=0 ROLE_FIELD="${ROLE_FIELD:-}" MARKFILE=/dev/null SC_ROLE=""
    # shellcheck disable=SC1090,SC1091
    source "$REPO/modules/srvctl/libs/authlib.sh"   # real sc_role
    # shellcheck disable=SC1090
    source "$STUBS"                                  # get returns ROLE_FIELD for 'role'
    # shellcheck disable=SC1090,SC1091
    source "$REPO/commonlib.sh"                      # real hint_on_file
    hint() { :; } ; complicate() { :; } ; title() { :; }
    if [[ $mode == indexed ]]
    then
      build_command_index "$file"
      $SC_IDX_BUILT || exit 199
    else
      # consumed by hint_on_file (sourced commonlib.sh); shellcheck can't see it
      # shellcheck disable=SC2034
      SC_IDX_BUILT=false                             # exercise the grep fallback filter
    fi
    hint_on_file "$file"
  ) > /dev/null 2>&1
  VISRC=$?
}
vis_no_authlib() { # $1 grep|indexed — fallback must ignore inherited SC_ROLE
  local mode file
  mode="${1:-grep}"
  file="$REPO/modules/srvctl/selftest/authfixtures/operatorsonly.sh"
  (
    set +u
    export SRVCTL=1 SC_INSTALL_DIR="$REPO" SC_USER=bob SC_UID0=false SC_HOSTNET=42 SC_ROLE=operator
    # shellcheck disable=SC1090,SC1091
    source "$REPO/commonlib.sh"                      # no authlib/sc_role on purpose
    hint() { :; } ; complicate() { :; } ; title() { :; }
    if [[ $mode == indexed ]]
    then
      build_command_index "$file"
      $SC_IDX_BUILT || exit 199
    else
      # shellcheck disable=SC2034
      SC_IDX_BUILT=false
    fi
    hint_on_file "$file"
  ) > /dev/null 2>&1
  VISRC=$?
}
vis_matrix() { # $1 grep|indexed
  local mode
  mode="$1"
# everyone: visible to every role
vis everyone root true "$mode"                 ; ok "$mode: root sees everyone"        "$(shown "$VISRC")" "shown"
ROLE_FIELD=operator vis everyone op false "$mode" ; ok "$mode: operator sees everyone" "$(shown "$VISRC")" "shown"
vis everyone bob false "$mode"                 ; ok "$mode: user sees everyone"        "$(shown "$VISRC")" "shown"
# root_only: only root
vis rootonly root true "$mode"                 ; ok "$mode: root sees root_only"       "$(shown "$VISRC")" "shown"
ROLE_FIELD=operator vis rootonly op false "$mode" ; ok "$mode: operator HIDDEN root_only" "$(shown "$VISRC")" "hidden"
vis rootonly bob false "$mode"                 ; ok "$mode: user HIDDEN root_only"     "$(shown "$VISRC")" "hidden"
# operators_only: root + operator
vis operatorsonly root true "$mode"            ; ok "$mode: root sees operators_only"  "$(shown "$VISRC")" "shown"
ROLE_FIELD=operator vis operatorsonly op false "$mode" ; ok "$mode: operator sees operators_only" "$(shown "$VISRC")" "shown"
vis operatorsonly bob false "$mode"            ; ok "$mode: user HIDDEN operators_only" "$(shown "$VISRC")" "hidden"
# owner_only: resource-scoped, always LISTED (enforced per-resource at run time)
vis owneronly root true "$mode"                ; ok "$mode: root sees owner_only"      "$(shown "$VISRC")" "shown"
ROLE_FIELD=operator vis owneronly op false "$mode" ; ok "$mode: operator sees owner_only" "$(shown "$VISRC")" "shown"
vis owneronly bob false "$mode"                ; ok "$mode: user sees owner_only"      "$(shown "$VISRC")" "shown"
# marker parser: guard calls are whole-file + line-anchored.
ROLE_FIELD=operator vis lateoperators op false "$mode" ; ok "$mode: operator sees late operators_only" "$(shown "$VISRC")" "shown"
vis lateoperators bob false "$mode"            ; ok "$mode: user HIDDEN late operators_only" "$(shown "$VISRC")" "hidden"
vis commentedroot bob false "$mode"            ; ok "$mode: user sees commented root_only" "$(shown "$VISRC")" "shown"
}
vis_matrix grep
vis_matrix indexed
vis_no_authlib grep                        ; ok "grep fallback ignores inherited SC_ROLE spoof"    "$(shown "$VISRC")" "hidden"
vis_no_authlib indexed                     ; ok "indexed fallback ignores inherited SC_ROLE spoof" "$(shown "$VISRC")" "hidden"

echo "== (F) default container service hook is owner-gated =="
svc_tmp="$(mktemp -d /tmp/srvctl-authgate.XXXXXX)"
mkdir -p "$svc_tmp/rootfs"
svc_rel="../tmp/${svc_tmp##*/}"
CMDS_adjust="service='$svc_rel'; op=start; source $REPO/modules/containers/hooks/adjust-service.sh; [[ \$service == srvctl-nspawn@* ]] && mark rewrite"

probe "$CMDS_adjust" mallory false
ok "adjust-service: non-owner DENIED (exit 44)" "$RC" "44"
ok "adjust-service: non-owner ran NO action"    "$(has_action "$MARKS")" "no"
ok "adjust-service: non-owner did NOT rewrite"  "$(has_mark "$MARKS" rewrite)" "no"
probe "$CMDS_adjust" alice false
ok "adjust-service: owner ESCALATES"            "$(has_mark "$MARKS" sudomize)" "yes"
probe "$CMDS_adjust" root true
ok "adjust-service: genuine root rewrites container unit" "$(has_mark "$MARKS" rewrite)" "yes"
probe "$CMDS_adjust" mallory true      # uid 0 via sudo, SC_USER != root, not owner
ok "adjust-service: SUDO-BYPASS (uid0 non-owner) DENIED" "$RC" "44"
ok "adjust-service: SUDO-BYPASS did NOT rewrite"         "$(has_mark "$MARKS" rewrite)" "no"
command rm -rf "$svc_tmp"

echo "== (G) generic 'sc <service> <op>' shorthand: host services root-gated =="
# command.sh sets ok=true when systemctl is-active succeeds (stubbed 0), then
# gates a mutating GENERIC host-service op with root_only before service_action.
# Policy: arbitrary host-service mutation (sshd/postfix/...) is root-only;
# operators use explicit reviewed commands. Reads (status) stay open.
SVC_STOP="CMD=sshd; ARG=stop; source $REPO/modules/srvctl/command.sh"
SVC_STATUS="CMD=sshd; ARG=status; source $REPO/modules/srvctl/command.sh"
probe "$SVC_STOP" mallory true                 # uid 0 via sudo, not root
ok "host-svc stop: sudo-bypass (uid0 non-root) DENIED"   "$RC" "44"
ok "host-svc stop: sudo-bypass reached NO service_action" "$(has_mark "$MARKS" service_action)" "no"
ROLE_FIELD=operator probe "$SVC_STOP" bob true ; ok "host-svc stop: operator DENIED (root-only)" "$RC" "44"
probe "$SVC_STOP" root true                    ; ok "host-svc stop: genuine root ALLOWED" "$(has_mark "$MARKS" service_action)" "yes"
probe "$SVC_STATUS" mallory false              ; ok "host-svc status: open to any user"   "$(has_mark "$MARKS" service_action)" "yes"

echo "== (G2) container shorthand 'sc VE <op>' stays OWNER-scoped (not re-denied) =="
# Full flow through the REAL container hook: it owner_only-authorizes and
# rewrites service=srvctl-nspawn@VE; command.sh must NOT re-deny the owner with
# the generic root_only gate (that regression broke `sc VE restart`).
ctr_tmp="$(mktemp -d /tmp/srvctl-authgate.XXXXXX)"; mkdir -p "$ctr_tmp/rootfs"
ctr_rel="../tmp/${ctr_tmp##*/}"   # /srv/$ctr_rel/rootfs resolves into $ctr_tmp
CTR_RESTART="run_hook() { [[ \$1 == adjust-service ]] && source $REPO/modules/containers/hooks/adjust-service.sh; }; CMD='$ctr_rel'; ARG=restart; source $REPO/modules/srvctl/command.sh"
probe "$CTR_RESTART" alice true                ; ok "sc VE restart: OWNER allowed (gate skips container unit)" "$(has_mark "$MARKS" service_action)" "yes"
probe "$CTR_RESTART" mallory true              # uid 0 via sudo, not the owner
ok "sc VE restart: sudo-bypass non-owner DENIED"        "$RC" "44"
ok "sc VE restart: non-owner reached NO service_action" "$(has_mark "$MARKS" service_action)" "no"
command rm -rf "$ctr_tmp"

echo "== (G4) typing the container UNIT NAME directly must NOT skip the root gate =="
# `sc srvctl-nspawn@victim stop` runs the REAL container hook, but there is no
# /srv/srvctl-nspawn@victim/rootfs, so owner_only never runs and the capability
# token SC_SERVICE_OWNER_AUTHORIZED stays false — the generic root gate applies.
# (The earlier name-based skip let this reach service_action as uid 0.)
UNIT="run_hook() { [[ \$1 == adjust-service ]] && source $REPO/modules/containers/hooks/adjust-service.sh; }; CMD='srvctl-nspawn@victim'; ARG=stop; source $REPO/modules/srvctl/command.sh"
probe "$UNIT" mallory true
ok "direct unit stop: sudo-bypass DENIED"           "$RC" "44"
ok "direct unit stop: reached NO service_action"    "$(has_mark "$MARKS" service_action)" "no"
probe "$UNIT" root true                             ; ok "direct unit stop: genuine root ALLOWED (host-svc policy)" "$(has_mark "$MARKS" service_action)" "yes"

echo "== (G5) container machinectl shorthand ('sc poweroff VE') is owner-scoped =="
# op-first order: service=\$CMD=poweroff is NOT a container, so the srvctl
# container hook never fires; containers/command.sh reaches machinectl. Force
# is-active to FAIL so srvctl/command.sh falls through to that path.
ctr2_tmp="$(mktemp -d /tmp/srvctl-authgate.XXXXXX)"
ctr2_rel="../tmp/${ctr2_tmp##*/}"   # /srv/$ctr2_rel resolves into $ctr2_tmp
POWEROFF="systemctl() { [[ \$1 == is-active ]] && return 1; mark systemctl; }; CMD=poweroff; ARG='$ctr2_rel'; source $REPO/modules/containers/command.sh"
probe "$POWEROFF" mallory true                      ; ok "sc poweroff VE: sudo-bypass (non-owner) DENIED" "$RC" "44"
probe "$POWEROFF" alice true                        ; ok "sc poweroff VE: owner ALLOWED (reaches op)"      "$RC" "0"
command rm -rf "$ctr2_tmp"

echo "== (G3) openvpn hook calls service_action directly -> needs its own root gate =="
# The openvpn hook runs BEFORE command.sh's gate (it acts then returns 0). Its
# own guard runs before the unit-layout detection, so it is host-independent.
OVPN_STOP="service=openvpn; op=stop; source $REPO/modules/openvpn/hooks/adjust-service.sh"
OVPN_STATUS="service=openvpn; op=status; source $REPO/modules/openvpn/hooks/adjust-service.sh"
probe "$OVPN_STOP" mallory true                ; ok "openvpn stop: sudo-bypass (uid0 non-root) DENIED" "$RC" "44"
probe "$OVPN_STOP" mallory false               ; ok "openvpn stop: normal user DENIED (root-only)"     "$RC" "44"
probe "$OVPN_STOP" root true                   ; ok "openvpn stop: genuine root NOT denied"  "$(has_mark "$MARKS" err)" "no"
probe "$OVPN_STATUS" mallory false             ; ok "openvpn status: open to any user"       "$(has_mark "$MARKS" err)" "no"

echo "== (H) VE-side: guards defined without the containers module + add-user guarded =="
# Inside a VE the containers module is INACTIVE; srvctl authlib is always
# loaded. ve_only/hs_only were moved there, so they must be DEFINED with only
# srvctl authlib sourced (previously undefined inside a VE).
# shellcheck disable=SC1091
vedef() { ( source "$REPO/modules/srvctl/libs/authlib.sh" > /dev/null 2>&1; type "$1" > /dev/null 2>&1 && echo defined || echo undefined ); }
ok "VE-context: ve_only DEFINED (moved to srvctl authlib)" "$(vedef ve_only)" "defined"
ok "VE-context: hs_only DEFINED (moved to srvctl authlib)" "$(vedef hs_only)" "defined"
# add-user (container account/password mutation) is now root_only.
ADDUSER="source $REPO/modules/usersonve/commands/add-user.sh"
probe "$ADDUSER" mallory true                  ; ok "add-user: sudo-bypass (uid0 non-root) DENIED" "$RC" "44"
probe "$ADDUSER" bob false                      ; ok "add-user: normal VE user DENIED"              "$RC" "44"
ADDUSER_ROOT="adduser() { mark adduser; }; id() { return 1; }; getent() { echo 'x:x:0:0::/nonexistent-home:/bin/sh'; }; new_password() { echo pw; }; passwd() { :; }; mail() { :; }; $ADDUSER"
probe "$ADDUSER_ROOT" root true                ; ok "add-user: VE root reaches account creation"   "$(has_mark "$MARKS" adduser)" "yes"

command rm -f "$STUBS"
echo ""
echo "authgate.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
