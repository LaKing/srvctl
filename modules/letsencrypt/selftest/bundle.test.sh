#!/bin/bash
#
# modules/letsencrypt/selftest/bundle.test.sh — deployed bundle composition.
#
# Generates real certificates with openssl (an expired root, a valid
# intermediate, a valid leaf) and drives libs/bundlelib.js to prove: a bundle
# is the private key followed by certbot's fullchain and nothing else; a
# bundle written by an earlier version with the expired DST Root CA X3
# appended is detected as carrying an expired block (so letsencrypt.js
# rebuilds it); a clean bundle is not.
#
# Run: bash modules/letsencrypt/selftest/bundle.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
LIB="$REPO/modules/letsencrypt/libs/bundlelib.js"

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

# expired self-signed root (valid window entirely in the past)
openssl req -x509 -newkey rsa:2048 -nodes -keyout root.key -out root.crt \
  -subj "/O=Selftest/CN=Expired Root" -days 1 -not_before 20200101000000Z -not_after 20200102000000Z > /dev/null 2>&1
# valid intermediate and a leaf issued by it
openssl req -x509 -newkey rsa:2048 -nodes -keyout int.key -out int.crt -subj "/O=Selftest/CN=Intermediate" -days 30 > /dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=selftest.example" > /dev/null 2>&1
openssl x509 -req -in leaf.csr -CA int.crt -CAkey int.key -CAcreateserial -out leaf.crt -days 30 > /dev/null 2>&1

ok "expired root really is expired" "$(openssl x509 -checkend 0 -noout -in root.crt > /dev/null 2>&1 && echo valid || echo expired)" "expired"
ok "leaf really is valid" "$(openssl x509 -checkend 0 -noout -in leaf.crt > /dev/null 2>&1 && echo valid || echo expired)" "valid"

# certbot layout: fullchain = leaf + intermediate; strip the trailing newline
# from fullchain to prove composeBundle normalises it.
{ cat leaf.crt; cat int.crt; } > fullchain.pem
printf '%s' "$(cat fullchain.pem)" > fullchain-nonl.pem

node - "$LIB" "$TMP" <<'JS'
const lib = require(process.argv[2]);
const fs = require("fs");
const dir = process.argv[3];
const read = (f) => fs.readFileSync(dir + "/" + f, "utf8");
const out = {};

const bundle = lib.composeBundle(read("leaf.key"), read("fullchain-nonl.pem"));
out.blocks = lib.certificateBlocks(bundle).length;
out.startsWithKey = bundle.indexOf("-----BEGIN PRIVATE KEY-----") === 0;
out.leafFirst = lib.certificateBlocks(bundle)[0].trim() === read("leaf.crt").trim();
out.singleTrailingNewline = /[^\n]\n$/.test(bundle);
out.cleanExpired = JSON.stringify(lib.expiredBlocks(bundle));

const legacy = read("leaf.key") + "\n" + read("fullchain.pem") + "\n" + read("root.crt") + "\n";
out.legacyBlocks = lib.certificateBlocks(legacy).length;
out.legacyExpired = JSON.stringify(lib.expiredBlocks(legacy));

out.garbageExpired = JSON.stringify(lib.expiredBlocks("-----BEGIN CERTIFICATE-----\nnot base64\n-----END CERTIFICATE-----\n"));
out.noBlocks = JSON.stringify(lib.expiredBlocks(read("leaf.key")));

fs.writeFileSync(dir + "/out.json", JSON.stringify(out));
JS

get() { node -e 'const o=require(process.argv[1]); console.log(String(o[process.argv[2]]))' "$TMP/out.json" "$1"; }

ok "bundle carries exactly leaf and intermediate" "$(get blocks)" "2"
ok "bundle starts with the private key" "$(get startsWithKey)" "true"
ok "leaf is the first certificate block" "$(get leafFirst)" "true"
ok "bundle ends with a single newline" "$(get singleTrailingNewline)" "true"
ok "clean bundle has no expired block" "$(get cleanExpired)" "[]"
ok "legacy bundle has three blocks" "$(get legacyBlocks)" "3"
ok "legacy bundle's appended root is reported expired" "$(get legacyExpired)" "[2]"
ok "an unreadable block counts as expired" "$(get garbageExpired)" "[0]"
ok "a key-only text has no certificate blocks" "$(get noBlocks)" "[]"

echo "bundle.test.sh: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
