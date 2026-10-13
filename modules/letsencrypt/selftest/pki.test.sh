#!/bin/bash
#
# modules/letsencrypt/selftest/pki.test.sh — container TLS file contents and
# modes (pkilib.js), against fixture roots only, never the live /srv.
#
# Generates a CA and a leaf with openssl and checks:
#  a. deploy over targets pre-created at 0644 holding the pre-fix
#     key+fullchain bundle: private/localhost.key and the datastore bundle end
#     at exactly 0600 (an explicit chmod, which a creation mode would miss),
#     the datastore bundle is still composeBundle's privkey + fullchain, and
#     certs/ holds the fullchain only;
#  b. the same on a fresh rootfs;
#  c. the legacy sweep: strips keys from certs/<C>.pem and certs/localhost.pem
#     (only those), narrows localhost.key, never follows a symlink out of the
#     rootfs, and a second pass changes nothing;
#  d. a whole letsencrypt.js run (stub certbot, the http01-cap.test.mjs
#     environment) cleans containers that never reach letsencrypt_deploy:
#     mail./devel/dotless names, a still-valid datastore certificate, a
#     failed issuance without a lineage and a /srv dir unknown to the
#     datastore;
#  e. a FIFO planted at private/localhost.key or certs/localhost.pem is
#     reported as an error without blocking; the rest of that container and
#     the other containers are still cleaned and deployed;
#  f. certs/ or private/ swapped for a symlink to an outside directory right
#     after pkilib opened it: outside files keep their bytes and mode, the
#     swap is reported, and deploy writes no certs after it.
# Case d also proves certbot's log goes under the fixture root, not /srv.
# Offline: openssl and node only.
#
# Run: bash modules/letsencrypt/selftest/pki.test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
LIB="$REPO/modules/letsencrypt/pkilib.js"
BUNDLE="$REPO/modules/letsencrypt/bundlelib.js"

pass=0; fail=0
ok() { if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

q() { "$@" > /dev/null 2>&1; }
q openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -subj "/O=Selftest/CN=CA" -days 30
q openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=selftest.example"
q openssl x509 -req -in leaf.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out leaf.crt -days 30
q openssl req -x509 -newkey rsa:2048 -nodes -keyout ph.key -out ph.crt -subj "/CN=placeholder.test" -days 3650
cat leaf.crt ca.crt > fullchain.pem
# what letsencrypt_deploy wrote into certs/ before this fix
cat leaf.key leaf.crt ca.crt > legacy.pem

mode() { stat -c %a "$1"; }
same() { cmp -s "$1" "$2" && echo same || echo differs; }
keys() { grep -rl -- 'PRIVATE KEY' "$@" 2>/dev/null | wc -l; }
certs() { grep -c -- '-----BEGIN CERTIFICATE-----' "$1"; }
pki() { echo "$1/$2/rootfs/etc/pki/tls"; }

# legacy ROOT NAME — a container as deployed before the fix, all 0644
legacy() {
    local d; d="$(pki "$1" "$2")"
    mkdir -p "$d/private" "$d/certs"
    cp legacy.pem "$d/certs/$2.pem"; cp legacy.pem "$d/certs/localhost.pem"; cp leaf.key "$d/private/localhost.key"
    chmod 644 "$d/certs/$2.pem" "$d/certs/localhost.pem" "$d/private/localhost.key"
}

# sweep ROOT — sorted "action[:code] relative-path" lines
sweep() {
    node -e '
const l = require(process.argv[1]);
const root = process.argv[2];
console.log(l.sweepContainers(root).map((c) => c.action + (c.error ? ":" + c.error : "") + " " + c.file.slice(root.length + 1)).sort().join("\n"));
' "$LIB" "$1"
}

# deploy ROOT NAME — "deployed=<bool> errors=<file:code ...>"
deploy() {
    node -e '
const l = require(process.argv[1]);
const fs = require("fs");
const root = process.argv[2], name = process.argv[3];
const r = l.deployContainer(root, name, fs.readFileSync("leaf.key", "utf8"), fs.readFileSync("fullchain.pem", "utf8"));
const pki = root + "/" + name + "/rootfs/etc/pki/tls/";
console.log("deployed=" + r.deployed + " errors=" + r.errors.map((e) => e.file.slice(pki.length) + ":" + e.error).join(" "));
' "$LIB" "$1" "$2"
}

# --- a. deploy over pre-existing 0644 targets --------------------------------
A="$TMP/a"
legacy "$A" dep.test
d="$(pki "$A" dep.test)"
printf 'old\n' > "$d/certs/localhost.crt"; chmod 644 "$d/certs/localhost.crt"
cp legacy.pem "$TMP/a-datastore.pem"; chmod 644 "$TMP/a-datastore.pem"
ok "a: targets really start at 0644" "$(mode "$d/private/localhost.key") $(mode "$TMP/a-datastore.pem")" "644 644"
ok "a: deploy result" "$(deploy "$A" dep.test)" "deployed=true errors="
# the datastore write as letsencrypt_deploy does it
node -e '
const l = require(process.argv[1]), b = require(process.argv[2]), fs = require("fs");
l.writeFile(process.argv[3], b.composeBundle(fs.readFileSync("leaf.key", "utf8"), fs.readFileSync("fullchain.pem", "utf8")), 0o600);
' "$LIB" "$BUNDLE" "$TMP/a-datastore.pem"
ok "a: localhost.key narrowed to 0600" "$(mode "$d/private/localhost.key")" "600"
ok "a: localhost.key is the private key" "$(same "$d/private/localhost.key" leaf.key)" "same"
ok "a: localhost.key owner is private/'s" "$(stat -c %u:%g "$d/private/localhost.key")" "$(stat -c %u:%g "$d/private")"
ok "a: datastore bundle narrowed to 0600" "$(mode "$TMP/a-datastore.pem")" "600"
ok "a: datastore bundle is privkey + fullchain" "$(same "$TMP/a-datastore.pem" <(cat leaf.key fullchain.pem))" "same"
for f in localhost.crt dep.test.pem localhost.pem; do
    ok "a: certs/$f is the fullchain" "$(same "$d/certs/$f" fullchain.pem)" "same"
    ok "a: certs/$f is 0644" "$(mode "$d/certs/$f")" "644"
done
ok "a: no PRIVATE KEY in certs/" "$(keys "$d/certs")" "0"

# --- b. fresh rootfs ------------------------------------------------------------
B="$TMP/b"
d="$(pki "$B" new.test)"
mkdir -p "$d/private" "$d/certs"
ok "b: deploy result" "$(deploy "$B" new.test)" "deployed=true errors="
ok "b: new localhost.key is 0600" "$(mode "$d/private/localhost.key")" "600"
ok "b: new certs files are 0644" "$(mode "$d/certs/localhost.crt") $(mode "$d/certs/new.test.pem") $(mode "$d/certs/localhost.pem")" "644 644 644"
ok "b: no PRIVATE KEY in certs/" "$(keys "$d/certs")" "0"
ok "b: no rootfs, no deploy" "$(deploy "$B" absent.test)" "deployed=false errors="

# --- c. legacy sweep --------------------------------------------------------------
S="$TMP/c"
legacy "$S" old.test
legacy "$S" postfix.test
cp legacy.pem "$(pki "$S" postfix.test)/certs/postfix.pem"
d="$(pki "$S" clean.test)"; mkdir -p "$d/private" "$d/certs"
cp fullchain.pem "$d/certs/clean.test.pem"; cp fullchain.pem "$d/certs/localhost.pem"; cp leaf.key "$d/private/localhost.key"; chmod 600 "$d/private/localhost.key"
mkdir -p "$S/nopki.test/rootfs"
# symlinks the container root could plant, pointing at host files
cp legacy.pem outside-key.pem; cp leaf.key outside.key; chmod 644 outside.key
d="$(pki "$S" linkpem.test)"; mkdir -p "$d/private" "$d/certs"; ln -s "$TMP/outside-key.pem" "$d/certs/localhost.pem"
d="$(pki "$S" linkkey.test)"; mkdir -p "$d/private" "$d/certs"; ln -s "$TMP/outside.key" "$d/private/localhost.key"
mkdir -p outside-certs; cp legacy.pem outside-certs/localhost.pem
d="$(pki "$S" linkdir.test)"; mkdir -p "$d/private"; ln -s "$TMP/outside-certs" "$d/certs"
legacy "$TMP/outside-etc" etc.test
mkdir -p "$S/linketc.test/rootfs"; ln -s "$TMP/outside-etc/etc.test/rootfs/etc" "$S/linketc.test/rootfs/etc"

T=rootfs/etc/pki/tls
ok "c: first sweep" "$(sweep "$S")" "$(printf '%s\n' \
    "error:ENOTDIR linkdir.test/$T" \
    "error:ENOTDIR linketc.test/$T" \
    "error:ENOTREG linkkey.test/$T/private/localhost.key" \
    "error:ENOTREG linkpem.test/$T/certs/localhost.pem" \
    "narrowed old.test/$T/private/localhost.key" \
    "narrowed postfix.test/$T/private/localhost.key" \
    "stripped old.test/$T/certs/localhost.pem" \
    "stripped old.test/$T/certs/old.test.pem" \
    "stripped postfix.test/$T/certs/localhost.pem" \
    "stripped postfix.test/$T/certs/postfix.test.pem")"
d="$(pki "$S" old.test)"
ok "c: no PRIVATE KEY left in certs/" "$(keys "$d/certs")" "0"
ok "c: stripped files keep their certificates" "$(certs "$d/certs/old.test.pem") $(certs "$d/certs/localhost.pem")" "2 2"
ok "c: stripped file is the fullchain" "$(same "$d/certs/localhost.pem" fullchain.pem)" "same"
ok "c: localhost.key narrowed to 0600" "$(mode "$d/private/localhost.key")" "600"
ok "c: postfix.pem is not touched" "$(same "$(pki "$S" postfix.test)/certs/postfix.pem" legacy.pem)" "same"
ok "c: symlinked certs file's target untouched" "$(same outside-key.pem legacy.pem)" "same"
ok "c: symlinked key's target keeps its mode" "$(mode outside.key)" "644"
ok "c: symlinked certs dir is skipped" "$(same outside-certs/localhost.pem legacy.pem)" "same"
ok "c: symlinked etc is skipped" "$(keys "$(pki "$TMP/outside-etc" etc.test)/certs")" "2"
ok "c: second sweep changes nothing" "$(sweep "$S" | grep -cv '^error')" "0"

# --- e. FIFOs (bounded) -------------------------------------------------------------
F="$TMP/e"
legacy "$F" fa.test; legacy "$F" fb.test; legacy "$F" fc.test
fa="$(pki "$F" fa.test)"; fb="$(pki "$F" fb.test)"
rm "$fa/private/localhost.key"; mkfifo "$fa/private/localhost.key"
rm "$fb/certs/localhost.pem"; mkfifo "$fb/certs/localhost.pem"
printf 'old\n' > "$fa/certs/localhost.crt"
out="$(timeout 20 bash -c "$(declare -f sweep deploy); LIB='$LIB'; sweep '$F'; echo ---; deploy '$F' fa.test; deploy '$F' fb.test; deploy '$F' fc.test")"
ok "e: sweep and deploy finish (no hang on a FIFO)" "$?" "0"
ok "e: FIFOs reported, everything else cleaned and deployed" "$out" "$(printf '%s\n' \
    "error:ENOTREG fa.test/$T/private/localhost.key" \
    "error:ENOTREG fb.test/$T/certs/localhost.pem" \
    "narrowed fb.test/$T/private/localhost.key" \
    "narrowed fc.test/$T/private/localhost.key" \
    "stripped fa.test/$T/certs/fa.test.pem" \
    "stripped fa.test/$T/certs/localhost.pem" \
    "stripped fb.test/$T/certs/fb.test.pem" \
    "stripped fc.test/$T/certs/fc.test.pem" \
    "stripped fc.test/$T/certs/localhost.pem" \
    "---" \
    "deployed=false errors=private/localhost.key:ENOTREG" \
    "deployed=false errors=certs/localhost.pem:ENOTREG" \
    "deployed=true errors=")"
ok "e: key failed, so fa.test's certificate is left as it was" "$(cat "$fa/certs/localhost.crt")" "old"
ok "e: fb.test still got its key and certificate" "$(same "$fb/private/localhost.key" leaf.key) $(same "$fb/certs/localhost.crt" fullchain.pem)" "same same"
ok "e: FIFOs left in place" "$([[ -p $fa/private/localhost.key && -p $fb/certs/localhost.pem ]] && echo fifo)" "fifo"
# grep -r skips FIFOs it meets while recursing
ok "e: no PRIVATE KEY in any certs/" "$(keys "$F"/*/rootfs/etc/pki/tls/certs)" "0"

# --- d. a whole letsencrypt.js run --------------------------------------------------
W="$TMP/d"; ds="$W/ds"; srv="$W/srv"; bin="$W/bin"
mkdir -p "$ds/cert" "$bin"
host="$(node -p 'require("os").hostname()')"
printf '{"c1":{"%s":{"host_ip":"192.0.2.1"}}}\n' "$host" > "$W/clusters.json"
echo '{}' > "$ds/users.json"
echo '{"mail.x.test":{},"dotless":{},"y.devel":{},
  "z.test":{"dns":{"z.test":{"A":["192.0.2.1"],"NS":[]}}},
  "w.test":{"dns":{"w.test":{"A":["192.0.2.1"],"NS":[]}}}}' > "$ds/containers.json"
cat leaf.key leaf.crt ca.crt > "$ds/cert/z.test.pem"   # still valid: skipped before deploy
cat ph.key ph.crt > "$ds/cert/w.test.pem"              # placeholder: certbot runs and fails
for b in letsencrypt dig rsync; do printf '#!/bin/sh\nexit 1\n' > "$bin/$b"; chmod 755 "$bin/$b"; done
for c in mail.x.test dotless y.devel z.test w.test orphan.test fa.test fb.test; do legacy "$srv" "$c"; done
rm "$(pki "$srv" fa.test)/private/localhost.key"; mkfifo "$(pki "$srv" fa.test)/private/localhost.key"
rm "$(pki "$srv" fb.test)/certs/localhost.pem"; mkfifo "$(pki "$srv" fb.test)/certs/localhost.pem"
le() {
    env PATH="$bin:$PATH" SC_DATASTORE_DIR="$ds" SRVCTL_SELFTEST=true SRVCTL_SELFTEST_CLUSTERS_FILE="$W/clusters.json" \
        SRVCTL_SELFTEST_HOSTNAME="$host" SC_ACME_DIR="$W/acme" SC_CLUSTERS_FILE="$W/clusters.json" \
        SC_LE_LIVE_DIR="$W/live" SC_SRV_ROOT="$srv" SC_ACME_HOOK_LOCK="$W/hook.lock" SC_LETSENCRYPT_BIN="$bin/letsencrypt" \
        SC_DIG_BIN="$bin/dig" SC_RSYNC_BIN="$bin/rsync" SC_ACME_HTTP01_MAX_PER_RUN="" \
        timeout 120 node "$REPO/modules/letsencrypt/letsencrypt.js" 2>&1
}
out="$(le)"
ok "d: letsencrypt.js run completes" "$?" "0"
ok "d: certbot ran for w.test and failed" "$(grep -c 'certonly failure for  w.test' <<< "$out")" "1"
ok "d: certbot output goes to the fixture root" "$(grep -q -- ">> $srv/w.test/letsencryptw.test.log" <<< "$out" && echo cmd) $([[ -f $srv/w.test/letsencryptw.test.log ]] && echo exists)" "cmd exists"
ok "d: no live /srv path in any command" "$(grep -c -- '>> /srv/' <<< "$out")" "0"
for c in mail.x.test dotless y.devel z.test w.test orphan.test; do
    d="$(pki "$srv" "$c")"
    ok "d: $c certs/ cleaned, key 0600" "$(keys "$d/certs") $(mode "$d/private/localhost.key")" "0 600"
done
ok "d: FIFO key: certs still cleaned" "$(keys "$(pki "$srv" fa.test)/certs")" "0"
ok "d: FIFO certs file: rest cleaned" "$(keys "$(pki "$srv" fb.test)/certs/fb.test.pem") $(mode "$(pki "$srv" fb.test)/private/localhost.key")" "0 600"
ok "d: both FIFOs reported" "$(grep -c 'Container TLS cleanup failed for .*\(fa.test/rootfs/etc/pki/tls/private/localhost.key\|fb.test/rootfs/etc/pki/tls/certs/localhost.pem\)' <<< "$out")" "2"
out="$(le)"
ok "d: second run completes" "$?" "0"
ok "d: second run changes nothing" "$(grep -c 'Container TLS cleanup: ' <<< "$out")" "0"

# --- f. a directory swapped for a symlink after it was opened -----------------------
# The hook below renames certs/ or private/ and puts a symlink to an outside
# directory in its place right after pkilib opened it — the race a container
# root could win. Nothing outside may change; the swap is reported.
X="$TMP/f"
for c in swapc.test swapp.test swapd.test other.test; do legacy "$X" "$c"; done
mkdir -p f-out-certs f-out-private
cp legacy.pem f-out-certs/localhost.pem; cp legacy.pem f-out-certs/swapc.test.pem; cp leaf.key f-out-private/localhost.key
chmod 644 f-out-certs/* f-out-private/*
out="$(timeout 20 node - "$LIB" "$X" "$TMP" <<'JS'
const fs = require("fs");
const [lib, root, tmp] = process.argv.slice(2);
const swap = { "swapc.test": "certs", "swapp.test": "private", "swapd.test": "private" };
const outside = { certs: tmp + "/f-out-certs", private: tmp + "/f-out-private" };
const open = fs.openSync;
let container = null;
const armed = new Set(["swapc.test", "swapp.test"]);
fs.openSync = function (file) {
    const fd = open.apply(fs, arguments);
    const m = /\/([^/]+)\/rootfs$/.exec(file);
    if (m) container = m[1];
    const dir = swap[container];
    if (dir && armed.has(container) && file.endsWith("/" + dir)) {
        armed.delete(container);
        const real = root + "/" + container + "/rootfs/etc/pki/tls/" + dir;
        fs.renameSync(real, real + ".real");
        fs.symlinkSync(outside[dir], real);
    }
    return fd;
};
const l = require(lib);
console.log(l.sweepContainers(root).filter((c) => !c.file.includes("swapd.test"))
    .map((c) => c.action + (c.error ? ":" + c.error : "") + " " + c.file.slice(root.length + 1)).sort().join("\n"));
console.log("---");
armed.add("swapd.test");
const r = l.deployContainer(root, "swapd.test", fs.readFileSync(tmp + "/leaf.key", "utf8"), fs.readFileSync(tmp + "/fullchain.pem", "utf8"));
console.log("deployed=" + r.deployed + " errors=" + r.errors.map((e) => e.file.slice(root.length + 1) + ":" + e.error).join(" "));
JS
)"
ok "f: run finishes" "$?" "0"
ok "f: swaps reported, work stays inside the rootfs" "$out" "$(printf '%s\n' \
    "error:EMOVED swapc.test/$T/certs" \
    "error:EMOVED swapp.test/$T/private" \
    "narrowed other.test/$T/private/localhost.key" \
    "narrowed swapc.test/$T/private/localhost.key" \
    "narrowed swapp.test/$T/private/localhost.key" \
    "stripped other.test/$T/certs/localhost.pem" \
    "stripped other.test/$T/certs/other.test.pem" \
    "stripped swapc.test/$T/certs/localhost.pem" \
    "stripped swapc.test/$T/certs/swapc.test.pem" \
    "stripped swapp.test/$T/certs/localhost.pem" \
    "stripped swapp.test/$T/certs/swapp.test.pem" \
    "---" \
    "deployed=false errors=swapd.test/$T/private/localhost.key:EMOVED")"
ok "f: outside certs files byte-identical" "$(same f-out-certs/localhost.pem legacy.pem) $(same f-out-certs/swapc.test.pem legacy.pem)" "same same"
ok "f: outside files keep their mode" "$(mode f-out-certs/localhost.pem) $(mode f-out-certs/swapc.test.pem) $(mode f-out-private/localhost.key)" "644 644 644"
ok "f: outside key byte-identical" "$(same f-out-private/localhost.key leaf.key)" "same"
ok "f: the moved certs dir itself was cleaned" "$(keys "$(pki "$X" swapc.test)/certs.real")" "0"
ok "f: the moved private dir got the narrowing" "$(mode "$(pki "$X" swapp.test)/private.real/localhost.key")" "600"
ok "f: deploy wrote the key into the moved dir, not outside" "$(mode "$(pki "$X" swapd.test)/private.real/localhost.key")" "600"
ok "f: deploy wrote no certs after the swap" "$([[ -e $(pki "$X" swapd.test)/certs/localhost.crt ]] && echo written || echo none)" "none"

echo "pki.test.sh: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
