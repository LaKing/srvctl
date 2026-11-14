#!/bin/bash
# The put verb journals configuration changes in git but not measurements, and
# the list verb feeds a bash loop one row per record.
# Runs the real put, list and datastore_push against a sandbox repository;
# only main.mjs is replaced, by a stub that writes the record file (put) or
# prints the rows in $LIST_ROWS and exits with $LIST_EXIT (list).

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
if (verb === "list") {
    process.stdout.write(process.env.LIST_ROWS || "");
    process.stderr.write("LIST-WARNING: stub\n");
    process.exit(Number(process.env.LIST_EXIT || 0));
}
appendFileSync(`${process.env.SC_DATASTORE_RW_DIR}/${type}s/${id}.json`, `${verb} ${field} ${value}\n`);
EOF

# shellcheck disable=SC2034 # consumed by the sourced production functions
SC_DATASTORE_RO_USE=false SC_USER=tester NOW=now HOSTNAME=test.host
exif() { :; }
ntc() { :; }
errors=0
err() { errors=$((errors + 1)); }

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

# list: the documented loop, with a body command that reads stdin.
export LIST_ROWS=$'a.example\tnode1\t-\nb.example\t-\t10.1.2.3\n'
seen=""
while IFS=$'\t' read -r -u 3 C host ip
do
    cat > /dev/null
    seen+="$C|$host|$ip "
done 3< <(list container host ip 2> /dev/null) < <(echo "stdin a body command may read")
ok "a loop over list sees every row with its cells in place" "$seen" "a.example|node1|- b.example|-|10.1.2.3 "
ok "node's stderr stays out of the rows" "$(list container host ip 2> /dev/null | wc -l)" "2"

export LIST_ROWS=""
ok "no record prints no row" "$(list container 2> /dev/null | wc -l)" "0"

export LIST_ROWS=$'half\trow\n' LIST_EXIT=110
out="$(list container host 2> /dev/null)"
ok "a failed list returns the node exit code" "$?" "110"
ok "a failed list prints no row" "$out" ""
errors=0
list container host > /dev/null 2>&1
ok "a failed list is reported through err" "$errors" "1"

echo ""
echo "bashlib.test: $pass passed, $fail failed"
[[ $fail == 0 ]]
