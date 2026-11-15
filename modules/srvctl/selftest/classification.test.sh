#!/bin/bash
#
# modules/srvctl/selftest/classification.test.sh — WP-E.2.b-2 manifest.
#
# Asserts each classified command carries its agreed role guard, detected as a
# LINE-ANCHORED guard CALL (not a head-20 substring, so comments / commented-out
# markers do not count). This proves the classification is APPLIED; the guards
# themselves are proven behaviourally by authgate.test.sh (Parts D/E).
#
# The manifest grows as commands are classified. Commands NOT yet listed here
# are intentionally pending (see PENDING below) — they are NOT asserted.

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

# class of a command = its line-anchored guard call (priority: owner > ops >
# root > users > everyone).
detect() {
  local f="$1"
  grep -qE '^[[:space:]]*owner_only '                     "$f" && { echo owner_only;     return; }
  grep -qE '^[[:space:]]*operators_only[[:space:]]*$'     "$f" && { echo operators_only; return; }
  grep -qE '^[[:space:]]*root_only[[:space:]]*$'          "$f" && { echo root_only;      return; }
  grep -qE '^[[:space:]]*users_only[[:space:]]*$'         "$f" && { echo users_only;     return; }
  echo everyone
}

# module/command : expected class  (WP-E.2.b agreed classification — ALL 39)
declare -A MANIFEST=(
  # owner_only — resource-scoped (root or the resource owner)
  [containers/destroy-ve]=owner_only     [containers/remove-ve]=owner_only
  [containers/backup-ve]=owner_only      [containers/add-ve-user]=owner_only
  [containers/map-port]=owner_only       [containers/update-ve]=owner_only
  [haproxy/http-redirect]=owner_only     [haproxy/https-redirect]=owner_only
  [named/override-in-address]=owner_only [vncproxy/add-vnc-user]=owner_only
  # operators_only — provisioning + co-worker host tasks (root or operator)
  [usersonhost/add-user]=operators_only  [containers/add-network-ve]=operators_only
  [saslauthd/testsaslauthd]=operators_only [saslauthd/fix-saslauthd]=operators_only
  [containers/limit-ve]=operators_only
  # root_only — host/cluster admin, code, host maintenance
  [srvctl/update-install]=root_only      [usersonhost/add-reseller]=root_only
  [containers/recreate-ve]=root_only     [usersonhost/change-user]=root_only
  [containers/regenerate]=root_only      [srvctl/customize]=root_only
  [srvctl/fix-owner]=root_only           [srvctl/fix-sshd]=root_only
  [containers/exec-all]=root_only        [odoo/install-odoo]=root_only
  [containers/retire-ve]=root_only
  [wordpress/install-wordpress]=root_only
  # root_only — VE-side commands: container-admin (VE root) tasks. add-user was
  # UNGUARDED (WP-E VE-side sweep) — now guarded like its siblings.
  [usersonve/install-crossover]=root_only [usersonve/install-qlcplus]=root_only
  [usersonve/vnc-desktop]=root_only       [usersonve/add-zerotier]=root_only
  [usersonve/add-user]=root_only
  # users_only — acts for the caller himself (root or a user with a record)
  [containers/add-ve]=users_only          [usersonhost/add-publickey]=users_only
  [codepad/add-codepad]=users_only
  # everyone (default, no role guard) — reads; not startable through sudo
  [containers/status]=everyone           [ve/status]=everyone
  [srvctl/version]=everyone               [srvctl/ls]=everyone
  [srvctl/diagnose]=everyone
)

for key in "${!MANIFEST[@]}"; do
  mod="${key%%/*}"; name="${key#*/}"
  ok "$key" "$(detect "$REPO/modules/$mod/commands/$name.sh")" "${MANIFEST[$key]}"
done

echo ""
echo "classification.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
