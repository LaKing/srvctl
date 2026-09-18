// modules/letsencrypt/selftest/fixtures.mjs — shared fixtures for the
// letsencrypt node selftests: real openssl certificates relative to the real
// clock (the shared bash gate checks validity with openssl against "now"),
// temp dirs, a clusters.json and fake certbot/rsync binaries.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

export const REPO = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../../..");

export function tmpdir(prefix) {
    return fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), prefix || "le-test-"));
}

function stamp(ms) {
    return new Date(ms).toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z").replace("T", "");
}

// { key, cert } PEM texts. sans: array of DNS names (optional); cn: subject.
export function makeCert({ cn, sans, daysBefore = 1, daysAfter = 60 }) {
    const dir = tmpdir("cert-");
    const now = Date.now();
    const args = ["req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", path.join(dir, "k.pem"), "-out", path.join(dir, "c.pem"), "-subj", "/CN=" + cn,
        "-not_before", stamp(now - daysBefore * 86400000), "-not_after", stamp(now + daysAfter * 86400000)];
    if (sans) args.push("-addext", "subjectAltName=" + sans.map((s) => "DNS:" + s).join(","));
    execFileSync("openssl", args, { stdio: "ignore" });
    const out = { key: fs.readFileSync(path.join(dir, "k.pem"), "utf8"), cert: fs.readFileSync(path.join(dir, "c.pem"), "utf8") };
    fs.rmSync(dir, { recursive: true, force: true });
    return out;
}

export function foreignKey() {
    return makeCert({ cn: "foreign.invalid" }).key;
}

// Managed wildcard bundle text: key first, then the certificate.
export function makeBundle(base, opts = {}) {
    const c = makeCert({ cn: base, sans: opts.sans || [base, "*." + base], daysBefore: opts.daysBefore ?? 1, daysAfter: opts.daysAfter ?? 89 });
    return (opts.foreignKey ? foreignKey() : c.key) + c.cert;
}

// Per-domain certificate as letsencrypt_deploy writes it (key + fullchain).
export function makeDomainPem(domain, daysAfter, sans) {
    const c = makeCert({ cn: domain, sans: sans || [domain], daysBefore: 1, daysAfter });
    return c.key + c.cert;
}

export function write(file, text, mode) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text, { mode: mode || 0o600 });
}

export function writeClusters(dir) {
    const file = path.join(dir, "clusters.json");
    fs.writeFileSync(file, JSON.stringify({
        c1: {
            "r2.test": { host_ip: "192.0.2.2", dns_server: "master", dns_primary: true },
            "s1.test": { host_ip: "192.0.2.3", dns_server: "slave" },
            "h3.test": { host_ip: "192.0.2.4" },
        },
    }));
    return file;
}

// Fake certbot: records its argv; for --cert-name N writes live/N from a
// fresh 90-day wildcard (DNS-01) or plain (webroot) certificate. Exits 1
// when N is listed in $FAKE_LE_FAIL.
export function fakeCertbot(dir) {
    const bin = path.join(dir, "fake-letsencrypt");
    fs.writeFileSync(bin, `#!/bin/bash
echo "$*" >> "$FAKE_LE_LOG"
name="" ; prev=""
for a in "$@"; do [[ "$prev" == --cert-name ]] && name="$a"; prev="$a"; done
for f in \${FAKE_LE_FAIL:-}; do [[ "$f" == "$name" ]] && exit 1; done
base="\${name#srvctl-wildcard-}"
d="$SC_LE_LIVE_DIR/$name"; mkdir -p "$d"
if [[ "$*" == *--manual* ]]; then san="subjectAltName=DNS:$base,DNS:*.$base"; else san="subjectAltName=DNS:$base"; fi
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$d/privkey.pem" -out "$d/fullchain.pem" \\
  -subj "/CN=$base" -addext "$san" -days 90 > /dev/null 2>&1
`, { mode: 0o755 });
    return bin;
}

// Fake rsync: "-e ssh... root@host:/path local" copies $FAKE_REMOTE/path.
export function fakeRsync(dir) {
    const bin = path.join(dir, "fake-rsync");
    fs.writeFileSync(bin, `#!/bin/bash
[[ -n "\${FAKE_RSYNC_FAIL:-}" ]] && exit 12
src="\${@: -2:1}"; dst="\${@: -1}"
echo "$*" >> "\${FAKE_RSYNC_LOG:-/dev/null}"
cp "$FAKE_REMOTE\${src#*:}" "$dst"
`, { mode: 0o755 });
    return bin;
}

export function sha256(text) {
    return execFileSync("sha256sum", { input: text }).toString().split(" ")[0];
}
