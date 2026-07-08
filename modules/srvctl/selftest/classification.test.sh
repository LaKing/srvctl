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
# root > reseller > everyone).
detect() {
  local f="$1"
  grep -qE '^[[:space:]]*owner_only '                     "$f" && { echo owner_only;     return; }
  grep -qE '^[[:space:]]*operators_only[[:space:]]*$'     "$f" && { echo operators_only; return; }
  grep -qE '^[[:space:]]*root_only[[:space:]]*$'          "$f" && { echo root_only;      return; }
  grep -qE '^[[:space:]]*reseller_only[[:space:]]*$'      "$f" && { echo reseller_only;  return; }
  echo everyone
}

# module/command : expected class  (WP-E.2.b agreed classification)
declare -A MANIFEST=(
  # owner_only — resource-scoped (root or the resource owner)
  [containers/destroy-ve]=owner_only     [containers/remove-ve]=owner_only
  [containers/backup-ve]=owner_only      [containers/recreate-ve]=owner_only
  [containers/map-port]=owner_only       [haproxy/http-redirect]=owner_only
  [haproxy/https-redirect]=owner_only    [named/override-in-address]=owner_only
  [vncproxy/add-vnc-user]=owner_only
  # operators_only — provisioning (root or operator)
  [containers/add-ve]=operators_only     [containers/add-network-ve]=operators_only
  [codepad/add-codepad]=operators_only
  # root_only — host/cluster admin (pre-existing real guards)
  [srvctl/update-install]=root_only      [usersonhost/add-reseller]=root_only
)

for key in "${!MANIFEST[@]}"; do
  mod="${key%%/*}"; name="${key#*/}"
  ok "$key" "$(detect "$REPO/modules/$mod/commands/$name.sh")" "${MANIFEST[$key]}"
done

echo ""
echo "classification.test: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
