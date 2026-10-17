#!/bin/bash
# libs/cronlib.sh: the hourly regenerate job prints (so cron mails root) only
# when regenerate fails, keeps the last output in its log, and is rewritten
# only when its content changes. A fake srvctl.sh stands in for regenerate.
set -euo pipefail
SC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SRVCTL='srvctl-test'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=modules/containers/libs/cronlib.sh
source "$SC_INSTALL_DIR/modules/containers/libs/cronlib.sh"
msg() { echo "$*" >> "$tmp/messages"; }
expect() {
    [[ $2 == "$3" ]] || { echo "FAIL $1: expected '$2', got '$3'"; exit 1; }
    echo "PASS $1"
}

SC_INSTALL_DIR="$tmp/srvctl"
SC_CRON_REGENERATE_LOG="$tmp/regenerate.log"
mkdir -p "$SC_INSTALL_DIR"
job="$tmp/srvctl-regenerate.sh"

write_cron_regenerate "$job"
expect 'job written and reported' 1 "$(grep -c "wrote $job" "$tmp/messages")"
expect 'job executable' yes "$([[ -x $job ]] && echo yes)"

printf '%s\n' 'echo "regenerate output $*"' 'exit 0' > "$SC_INSTALL_DIR/srvctl.sh"
expect 'success: nothing for cron to mail' '' "$(bash "$job")"
expect 'success: output in the log' 'regenerate output regenerate #cron.hourly' "$(cat "$SC_CRON_REGENERATE_LOG")"

printf '%s\n' 'echo "broken hook"' 'exit 3' > "$SC_INSTALL_DIR/srvctl.sh"
out="$(bash "$job")"
expect 'failure: exit code reported' 'srvctl regenerate failed (exit 3), output:' "$(head -1 <<< "$out")"
expect 'failure: output mailed' 'broken hook' "$(tail -1 <<< "$out")"

: > "$tmp/messages"
write_cron_regenerate "$job"
expect 'unchanged job not rewritten' 0 "$(grep -c wrote "$tmp/messages" || true)"
SRVCTL='srvctl-other-version'
write_cron_regenerate "$job"
expect 'version change alone not rewritten' 0 "$(grep -c wrote "$tmp/messages" || true)"

printf '%s\n' '#!/bin/bash' '' "/bin/bash /usr/local/share/srvctl/srvctl.sh regenerate '#cron.hourly'" > "$job"
write_cron_regenerate "$job"
expect 'old job replaced' 1 "$(grep -c 'regenerate.log 2>&1' "$job")"

echo 'All containers cron tests passed.'
