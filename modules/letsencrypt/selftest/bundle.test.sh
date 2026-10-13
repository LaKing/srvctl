#!/bin/bash
#
# modules/letsencrypt/selftest/bundle.test.sh — deployed bundle composition.
#
# Generates a real chain with openssl (root -> intermediate -> leaf) in a
# fixture directory mirroring /etc/letsencrypt/live/<domain>, composes the
# served bundle with bundlelib.composeBundle as letsencrypt_deploy does, and
# checks every block of it with openssl: the private key comes first and
# matches the leaf; every certificate block after the leaf is unexpired, not
# self-signed, and issues the block before it; and there are no more blocks
# than the leaf and its intermediates (cert.pem + chain.pem). That check is
# proven to reject an expired, a self-signed or a non-issuing intermediate
# and an appended root, expired or still valid. A bundle as earlier versions
# wrote it (privkey + fullchain + the vendored, expired DST Root CA X3,
# reconstructed here) is rejected on its third block. Also covers
# composeBundle's newline handling and expiredBlocks, which letsencrypt.js
# uses to rebuild such legacy bundles. Offline: openssl and node only.
#
# Run: bash modules/letsencrypt/selftest/bundle.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
LIB="$REPO/modules/letsencrypt/bundlelib.js"

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

q() { "$@" > /dev/null 2>&1; }
V="openssl verify -no-CAfile -no-CApath -no-CAstore"
printf 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n' > ca.ext

# valid root (the trust anchor, never part of the bundle), an intermediate it
# issues, and a leaf issued by the intermediate
q openssl req -x509 -newkey rsa:2048 -nodes -keyout root.key -out root.crt -subj "/O=Selftest/CN=Root" -days 30
q openssl req -newkey rsa:2048 -nodes -keyout int.key -out int.csr -subj "/O=Selftest/CN=Intermediate"
q openssl x509 -req -in int.csr -CA root.crt -CAkey root.key -CAcreateserial -extfile ca.ext -out int.crt -days 30
q openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=selftest.example"
q openssl x509 -req -in leaf.csr -CA int.crt -CAkey int.key -CAcreateserial -out leaf.crt -days 30

# broken intermediates, each still carrying the leaf issuer's name: expired
# (same key, so it does issue the leaf), self-signed (same key) and unrelated
# (another key, so it does not issue the leaf)
q openssl x509 -req -in int.csr -CA root.crt -CAkey root.key -CAcreateserial -extfile ca.ext -out int-expired.crt \
  -not_before 20200101000000Z -not_after 20200102000000Z
q openssl x509 -req -in int.csr -key int.key -extfile ca.ext -out int-selfsigned.crt -days 30
q openssl req -newkey rsa:2048 -nodes -keyout other.key -out other.csr -subj "/O=Selftest/CN=Intermediate"
q openssl x509 -req -in other.csr -CA root.crt -CAkey root.key -CAcreateserial -extfile ca.ext -out int-other.crt -days 30

# Reconstruction of the vendored letsencrypt-ca.pem earlier versions appended
# (the original is no longer in the tree): self-signed, DST's subject and
# validity window, expired 2021-09-30.
q openssl req -x509 -newkey rsa:2048 -nodes -keyout dst.key -out dst.crt -subj "/O=Digital Signature Trust Co./CN=DST Root CA X3" \
  -not_before 20000930211240Z -not_after 20210930140115Z

ok "root really is valid" "$(openssl x509 -checkend 0 -noout -in root.crt > /dev/null 2>&1 && echo valid || echo expired)" "valid"
ok "DST root really is expired" "$(openssl x509 -checkend 0 -noout -in dst.crt > /dev/null 2>&1 && echo valid || echo expired)" "expired"
ok "leaf really is valid" "$(openssl x509 -checkend 0 -noout -in leaf.crt > /dev/null 2>&1 && echo valid || echo expired)" "valid"

# certbot layout; strip the trailing newline from fullchain to prove
# composeBundle normalises it.
LIVE="$TMP/live/selftest.example"
mkdir -p "$LIVE"
cp leaf.key "$LIVE/privkey.pem"
cp leaf.crt "$LIVE/cert.pem"
cp int.crt "$LIVE/chain.pem"
printf '%s' "$(cat leaf.crt int.crt)" > "$LIVE/fullchain.pem"

# chain_problems BUNDLE — every problem of a served bundle, or "ok":
# key-not-first, key-mismatch, expired:<i>, self-signed:<i>, not-issuer:<i>
# (block i does not issue block i-1), count:<n> (n != blocks in cert.pem +
# chain.pem). Blocks are numbered from 0, the leaf.
chain_problems() {
    local bundle="$1" dir n i problems=()
    dir="$(mktemp -d -p "$TMP")"
    head -n 1 "$bundle" | grep -qE '^-----BEGIN ([A-Z]+ )?PRIVATE KEY-----$' || problems+=(key-not-first)
    awk -v d="$dir" '/-----BEGIN CERTIFICATE-----/ { f = d "/" n++ ".pem" } f { print > f } /-----END CERTIFICATE-----/ { f = "" }' "$bundle"
    n="$(find "$dir" -name '*.pem' | wc -l)"
    [[ "$(openssl pkey -in "$bundle" -pubout 2>/dev/null)" == "$(openssl x509 -in "$dir/0.pem" -pubkey -noout 2>/dev/null)" ]] || problems+=(key-mismatch)
    for ((i = 1; i < n; i++)); do
        openssl x509 -checkend 0 -noout -in "$dir/$i.pem" > /dev/null 2>&1 || problems+=("expired:$i")
        $V -no_check_time -check_ss_sig -CAfile "$dir/$i.pem" "$dir/$i.pem" > /dev/null 2>&1 && problems+=("self-signed:$i")
        $V -no_check_time -partial_chain -trusted "$dir/$i.pem" "$dir/$((i - 1)).pem" > /dev/null 2>&1 || problems+=("not-issuer:$i")
    done
    [[ "$n" -eq "$(cat "$LIVE/cert.pem" "$LIVE/chain.pem" | grep -c -- '-----BEGIN CERTIFICATE-----')" ]] || problems+=("count:$n")
    if [[ ${#problems[@]} -eq 0 ]]; then echo ok; else echo "${problems[*]}"; fi
}

node - "$LIB" "$TMP" <<'JS'
const lib = require(process.argv[2]);
const fs = require("fs");
const dir = process.argv[3];
const read = (f) => fs.readFileSync(dir + "/" + f, "utf8");
const live = (f) => read("live/selftest.example/" + f);
const write = (f, text) => fs.writeFileSync(dir + "/" + f, text);
const out = {};

// as letsencrypt_deploy: privkey + fullchain from the live lineage
const bundle = lib.composeBundle(live("privkey.pem"), live("fullchain.pem"));
write("served.pem", bundle);
out.blocks = lib.certificateBlocks(bundle).length;
out.leafFirst = lib.certificateBlocks(bundle)[0].trim() === read("leaf.crt").trim();
out.singleTrailingNewline = /[^\n]\n$/.test(bundle);
out.cleanExpired = JSON.stringify(lib.expiredBlocks(bundle));

// served bundles whose fullchain is broken, composed the same way
const variant = (f, chain) => write(f, lib.composeBundle(live("privkey.pem"), chain.map(read).join("")));
variant("int-expired.pem", ["leaf.crt", "int-expired.crt"]);
variant("int-selfsigned.pem", ["leaf.crt", "int-selfsigned.crt"]);
variant("int-other.pem", ["leaf.crt", "int-other.crt"]);
variant("root-appended.pem", ["leaf.crt", "int.crt", "root.crt"]);
variant("swapped.pem", ["int.crt", "leaf.crt"]);
write("cert-first.pem", lib.composeBundle(live("fullchain.pem"), live("privkey.pem")));

// Reconstruction of the pre-fix letsencrypt_deploy composition:
// pem = privkey + fullchain + /etc/letsencrypt/ca.pem (DST Root CA X3).
const legacy = live("privkey.pem") + read("leaf.crt") + read("int.crt") + read("dst.crt");
write("legacy.pem", legacy);
out.legacyBlocks = lib.certificateBlocks(legacy).length;
out.legacyExpired = JSON.stringify(lib.expiredBlocks(legacy));

out.garbageExpired = JSON.stringify(lib.expiredBlocks("-----BEGIN CERTIFICATE-----\nnot base64\n-----END CERTIFICATE-----\n"));
out.noBlocks = JSON.stringify(lib.expiredBlocks(read("leaf.key")));

write("out.json", JSON.stringify(out));
JS

get() { node -e 'const o=require(process.argv[1]); console.log(String(o[process.argv[2]]))' "$TMP/out.json" "$1"; }

ok "bundle carries exactly leaf and intermediate" "$(get blocks)" "2"
ok "leaf is the first certificate block" "$(get leafFirst)" "true"
ok "bundle ends with a single newline" "$(get singleTrailingNewline)" "true"
ok "clean bundle has no expired block" "$(get cleanExpired)" "[]"

ok "served bundle: key first, valid chain, leaf + intermediates only" "$(chain_problems served.pem)" "ok"
ok "expired intermediate is rejected" "$(chain_problems int-expired.pem)" "expired:1"
ok "self-signed intermediate is rejected" "$(chain_problems int-selfsigned.pem)" "self-signed:1"
ok "intermediate not issuing the leaf is rejected" "$(chain_problems int-other.pem)" "not-issuer:1"
ok "appended valid root is rejected" "$(chain_problems root-appended.pem)" "self-signed:2 count:3"
ok "leaf after its intermediate is rejected" "$(chain_problems swapped.pem)" "key-mismatch not-issuer:1"
ok "certificate before the key is rejected" "$(chain_problems cert-first.pem)" "key-not-first"
ok "pre-fix bundle is rejected on the appended DST Root CA X3" "$(chain_problems legacy.pem)" "expired:2 self-signed:2 not-issuer:2 count:3"

ok "legacy bundle has three blocks" "$(get legacyBlocks)" "3"
ok "legacy bundle's appended root is reported expired" "$(get legacyExpired)" "[2]"
ok "an unreadable block counts as expired" "$(get garbageExpired)" "[0]"
ok "a key-only text has no certificate blocks" "$(get noBlocks)" "[]"

echo "bundle.test.sh: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
