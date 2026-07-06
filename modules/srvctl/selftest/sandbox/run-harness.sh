#!/bin/bash
#
# modules/srvctl/selftest/sandbox/run-harness.sh — run the REAL srvctl.sh
# help/dispatch path fully isolated from live srvctl state, so bash-runtime
# changes (WP-D command index, hooks, dispatch) can be golden-master tested on
# a dev box without touching /etc/srvctl, /var/srvctl3, /var/local/srvctl,
# /root, or the running v3 datastore.
#
# Isolation: an unprivileged user+mount namespace (unshare -Urm) with the live
# srvctl paths bind-shadowed by sandbox temp dirs. Writes inside the namespace
# land in the sandbox; live paths are physically unreachable. A checksum guard
# additionally fails the run if live /etc/srvctl or /var/srvctl3 changed.
#
# Usage:
#   run-harness.sh            compare captured output to the committed golden
#   run-harness.sh --record   (re)write the golden from current behavior
#
# Exit 0 = match (or recorded); non-zero = mismatch / guard tripped / no ns.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SANDBOX_SRC="$REPO/modules/srvctl/selftest/sandbox"
FIXTURES="$SANDBOX_SRC/fixture-modules"
GOLDEN_DIR="$SANDBOX_SRC/golden"
RECORD=false
[[ "${1:-}" == "--record" ]] && RECORD=true

# ---- preflight: unprivileged namespaces must be available -------------------
if ! unshare -Urmu true 2> /dev/null; then
  echo "SKIP: unprivileged user+mount+uts namespaces unavailable in this environment" >&2
  exit 0
fi

# ---- build the sandbox tree (outside the namespace) -------------------------
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
INSTALL="$SB/install"
mkdir -p "$INSTALL/modules" "$SB/etc" "$SB/var-local" "$SB/var-srvctl3/datastore" \
         "$SB/home" "$SB/var-log" "$SB/ds-rw" "$SB/ds-ro"

# REAL core scripts must be COPIED (srvctl.sh resolves realpath, so a symlink
# would point SC_INSTALL_DIR back at the repo and pull in the real 37 modules).
cp "$REPO/srvctl.sh" "$REPO/init.sh" "$REPO/commonlib.sh" "$REPO/lablib.sh" "$REPO/version" "$INSTALL/"
[[ -f "$REPO/lablib.js" ]] && cp "$REPO/lablib.js" "$INSTALL/"

# deterministic fixture modules
cp -r "$FIXTURES/." "$INSTALL/modules/"

# the srvctl module carries lib/commandindex.mjs (used once help is wired to it)
# but contributes no commands, so it does not affect the help listing.
mkdir -p "$INSTALL/modules/srvctl/lib"
cp "$REPO/modules/srvctl/lib/commandindex.mjs" "$INSTALL/modules/srvctl/lib/"
printf 'echo true\n' > "$INSTALL/modules/srvctl/module-condition.sh"

# minimal fixture config (a single *.conf sourced by init.sh)
cat > "$SB/etc/host.conf" << 'CONF'
SC_HOSTNET=42
SC_COMPANY_DOMAIN=harness.test
CONF

# ---- guard: checksum live paths BEFORE --------------------------------------
livesum() {
  { for p in /etc/srvctl /var/srvctl3; do
      [[ -e $p ]] && find "$p" -type f -exec sha256sum {} + 2> /dev/null
    done; } | sort | sha256sum
}
BEFORE="$(livesum)"

# ---- run the real srvctl.sh inside the isolated namespace -------------------
# $1 = srvctl args (e.g. "help"). stdout captured; stderr silenced (logs/notices).
run_sc() {
  unshare -Urmu bash -c '
    set -e
    hostname sc-sandbox   # UTS ns kernel hostname -> deterministic os.hostname()
    # Bash captures HOSTNAME at startup and only re-reads gethostname() when it
    # is NOT inherited; an exported HOSTNAME in the caller would otherwise leak
    # the real host name into srvctl output (lablib.sh msg/err). Force it.
    export HOSTNAME=sc-sandbox
    mount --bind "'"$SB"'/etc"          /etc/srvctl
    mount --bind "'"$SB"'/var-local"    /var/local/srvctl
    mount --bind "'"$SB"'/var-srvctl3"  /var/srvctl3
    mount --bind "'"$SB"'/home"         /root
    mount --bind "'"$SB"'/var-log"      /var/log
    export USER=root HOME=/root
    export SC_DATASTORE_RW_DIR="'"$SB"'/ds-rw" SC_DATASTORE_RO_DIR="'"$SB"'/ds-ro"
    cd /tmp
    bash "'"$INSTALL"'/srvctl.sh" '"$1"' 2>/dev/null
  '
}

# strip ANSI colour so the golden is stable across TTY/no-TTY
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }

HELP_OUT="$(run_sc help | strip_ansi || true)"   # help_commands (sc help)
BARE_OUT="$(run_sc '' | strip_ansi || true)"     # hint_commands (bare sc, exits 1)

# ---- guard: live paths must be UNCHANGED ------------------------------------
AFTER="$(livesum)"
if [[ "$BEFORE" != "$AFTER" ]]; then
  echo "GUARD TRIPPED: live /etc/srvctl or /var/srvctl3 changed during the harness run" >&2
  exit 2
fi

# ---- compare / record (help_commands + hint_commands) -----------------------
if $RECORD; then
  printf '%s\n' "$HELP_OUT" > "$GOLDEN_DIR/help.txt"
  printf '%s\n' "$BARE_OUT" > "$GOLDEN_DIR/bare.txt"
  echo "recorded goldens: help.txt ($(wc -l < "$GOLDEN_DIR/help.txt") lines), bare.txt ($(wc -l < "$GOLDEN_DIR/bare.txt") lines)"
  exit 0
fi

rc=0
for pair in "help.txt:$HELP_OUT" "bare.txt:$BARE_OUT"; do
  name="${pair%%:*}"; out="${pair#*:}"
  golden="$GOLDEN_DIR/$name"
  if [[ ! -f "$golden" ]]; then echo "no golden $name — run with --record first" >&2; exit 3; fi
  if diff -u "$golden" <(printf '%s\n' "$out"); then
    echo "sandbox-harness: $name matches golden ($(wc -l < "$golden") lines)"
  else
    echo "sandbox-harness: $name DIFFERS from golden" >&2; rc=1
  fi
done
[[ $rc -eq 0 ]] && echo "sandbox-harness: all goldens match, live paths untouched"
exit $rc
