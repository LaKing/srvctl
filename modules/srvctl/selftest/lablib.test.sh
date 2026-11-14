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
NOW=now
SC_USER=tester
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

# prune
SC_MOUNTINFO="$box/mountinfo"
: > "$SC_MOUNTINFO"
ntc() { :; }
mkdir -p "$box/left/dir/sub" "$box/keep"
echo data > "$box/keep/data"
echo x > "$box/left/file"
ln -s "$box/keep" "$box/left/link"

prune "$box/left/file" "$box/left/dir" "$box/left/link" "$box/left/missing"
ok "prune removes files, trees and links" "$(find "$box/left" -mindepth 1 | wc -l)" 0
ok "prune removes a link, not what it points to" "$(cat "$box/keep/data")" data
ok "prune writes each removal to the log" "$(grep -c ' prune ' "$SC_LOG")" 3

mkdir -p "$box/mounted/share"
echo "36 25 0:32 / $box/mounted/share rw - xfs /dev/md0 rw" > "$SC_MOUNTINFO"
prune "$box/mounted"
ok "prune refuses a tree with a mount in it" "$([[ -d $box/mounted/share ]] && echo kept)" kept
prune "$box/mounted/share"
ok "prune refuses a mount point" "$([[ -d $box/mounted/share ]] && echo kept)" kept
: > "$SC_MOUNTINFO"

mkdir -p "$box/a/b"
(cd "$box" && prune "a/b"; prune "$box/a/../a/b"; prune "$box/a/b/"; prune "/")
ok "prune refuses relative paths, '..', a trailing slash and /" "$([[ -d $box/a/b ]] && echo kept)" kept

SC_PRUNE_DRY_RUN=true prune "$box/a/b"
ok "a dry run removes nothing" "$([[ -d $box/a/b ]] && echo kept)" kept

echo ""
echo "lablib.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
