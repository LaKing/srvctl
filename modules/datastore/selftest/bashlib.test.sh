#!/bin/bash
# The put verb journals configuration changes in git but not measurements.
# Runs the real put and the real datastore_push against a sandbox repository;
# only main.mjs is replaced, by a stub that writes the record file.

# Test doubles are invoked indirectly by the sourced production functions.
# shellcheck disable=SC2329
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SANDBOX="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$SANDBOX"' EXIT

# put runs "/bin/node $SC_INSTALL_DIR/modules/datastore/main.mjs put ...".
SC_INSTALL_DIR="$SANDBOX/install"
SC_DATASTORE_RW_DIR="$SANDBOX/datastore"
export SC_DATASTORE_RW_DIR
mkdir -p "$SC_INSTALL_DIR/modules/datastore" "$SC_DATASTORE_RW_DIR"/{hosts,users,containers}
cat > "$SC_INSTALL_DIR/modules/datastore/main.mjs" << 'EOF'
import { appendFileSync } from "node:fs";
const [verb, type, id, field, value] = process.argv.slice(2);
appendFileSync(`${process.env.SC_DATASTORE_RW_DIR}/${type}s/${id}.json`, `${verb} ${field} ${value}\n`);
EOF

# shellcheck disable=SC2034 # consumed by the sourced production functions
SC_DATASTORE_RO_USE=false SC_USER=tester NOW=now HOSTNAME=test.host
exif() { :; }
ntc() { :; }

# shellcheck source=/dev/null
source "$REPO/modules/datastore/libs/gitlib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/datastore/libs/bashlib.sh"

git init -q "$SC_DATASTORE_RW_DIR"
git -C "$SC_DATASTORE_RW_DIR" config user.email tester@test.host
git -C "$SC_DATASTORE_RW_DIR" config user.name tester
echo seed > "$SC_DATASTORE_RW_DIR/containers/seed.json"
git -C "$SC_DATASTORE_RW_DIR" add -A
git -C "$SC_DATASTORE_RW_DIR" commit -q -m seed

pass=0
fail=0
ok() {
    if [[ $2 == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}
commits() { git -C "$SC_DATASTORE_RW_DIR" rev-list --count HEAD; }
committed() { git -C "$SC_DATASTORE_RW_DIR" show "HEAD:containers/$1.json" 2> /dev/null; }

put container a.example du 111
put container b.example du 222
ok "a measurement is stored" "$(cat "$SC_DATASTORE_RW_DIR/containers/a.example.json")" "put du 111"
ok "a measurement makes no commit" "$(commits)" "1"

put container a.example quota 500
ok "a configuration change makes one commit" "$(commits)" "2"
ok "that commit names the change" "$(git -C "$SC_DATASTORE_RW_DIR" log -1 --format=%s)" "tester@test.host put container a.example quota 500"
ok "that commit carries the earlier measurement of the same record" "$(committed a.example)" "put du 111"$'\n'"put quota 500"
ok "that commit carries the measurement of another record" "$(committed b.example)" "put du 222"

put container a.example duration 5
ok "a field that only starts like a measurement is journaled" "$(commits)" "3"

echo ""
echo "bashlib.test: $pass passed, $fail failed"
[[ $fail == 0 ]]
