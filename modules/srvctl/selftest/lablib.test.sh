#!/bin/bash
#
# modules/srvctl/selftest/lablib.test.sh — write_output never leaves a
# generated file empty or half-written.
# Run: bash modules/srvctl/selftest/lablib.test.sh

# shellcheck disable=SC2034,SC2329
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

pass=0
fail=0
ok() {
    if [[ "$2" == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}

box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
SC_LOG="$box/log"
# shellcheck source=/dev/null
source "$REPO/lablib.sh"
err() { :; }

f="$box/hosts"
good() { printf '127.0.0.1 localhost\n10.1.2.3 %s\n' "$1"; }
fails() { echo "partial"; return 112; }
silent() { :; }
## What a reader sees while the command is still running.
slow() { echo "new"; cat "$f" > "$box/seen-meanwhile"; }

write_output "$f" good a.example; ok "creates the file" $? 0
ok "content" "$(cat "$f")" $'127.0.0.1 localhost\n10.1.2.3 a.example'
ok "a new file is world-readable like a redirect would make it" "$(stat -c %a "$f")" 644

chmod 600 "$f"
inode="$(stat -c %i "$f")"
write_output "$f" good a.example; ok "unchanged rc" $? 0
ok "an unchanged file is not replaced" "$(stat -c %i "$f")" "$inode"

write_output "$f" good b.example
ok "a changed file gets the new content" "$(tail -1 "$f")" "10.1.2.3 b.example"
ok "and keeps its mode" "$(stat -c %a "$f")" 600

write_output "$f" fails; ok "a failed command returns non-zero" $? 1
ok "and leaves the last good content" "$(tail -1 "$f")" "10.1.2.3 b.example"
write_output "$f" silent; ok "empty output returns non-zero" $? 1
ok "and leaves the last good content" "$(tail -1 "$f")" "10.1.2.3 b.example"

write_output "$f" slow
ok "a reader never sees the file empty while it is generated" "$(cat "$box/seen-meanwhile")" $'127.0.0.1 localhost\n10.1.2.3 b.example'
ok "no temporary file is left behind" "$(find "$box" -name 'hosts.*' | wc -l)" 0

echo ""
echo "lablib.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
