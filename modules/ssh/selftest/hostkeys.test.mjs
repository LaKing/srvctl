// modules/ssh/lib/hostkeys.js — host-key revalidation and known_hosts tests.
// Runs without root: /srv is a temp dir, ssh-keyscan and systemctl are stubs.
// Usage: node modules/ssh/selftest/hostkeys.test.mjs

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const hk = require("../lib/hostkeys.js");

let passed = 0;
const failures = [];

function test(name, fn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "sc-ssh-hostkeys-"));
  try {
    fn(root);
    passed++;
    console.log(`  ok  ${name}`);
  } catch (error) {
    failures.push({ name, error });
    console.log(`FAIL  ${name}\n      ${error.stack || error}`);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

// A real ssh-rsa public key blob (base64), built with Node's crypto only.
function rsaKey() {
  const { publicKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 1024 });
  const jwk = publicKey.export({ format: "jwk" });
  const str = (b) => { const l = Buffer.alloc(4); l.writeUInt32BE(b.length); return Buffer.concat([l, b]); };
  const mpint = (b64u) => {
    let b = Buffer.from(b64u, "base64url");
    if (b[0] & 0x80) b = Buffer.concat([Buffer.from([0]), b]);
    return str(b);
  };
  return Buffer.concat([str(Buffer.from("ssh-rsa")), mpint(jwk.e), mpint(jwk.n)]).toString("base64");
}

const A = rsaKey();
const B = rsaKey();
const C = rsaKey();

function harness(root, { scans = {}, running = {} } = {}) {
  const calls = { scan: [], running: [] };
  const log = [];
  const opts = {
    srv_root: path.join(root, "srv"),
    keyscan(t) {
      calls.scan.push(t);
      const v = scans[t];
      if (v instanceof Error) throw v;
      return hk.parse_keyscan(v === undefined ? "" : v);
    },
    is_running(c) { calls.running.push(c); return running[c] === true; },
    log(text, kind) { log.push({ text, kind }); },
  };
  fs.mkdirSync(opts.srv_root, { recursive: true });
  return { opts, calls, log };
}

function localContainer(opts, c, cached) {
  fs.mkdirSync(path.join(opts.srv_root, c), { recursive: true });
  if (cached !== undefined) fs.writeFileSync(path.join(opts.srv_root, c, "host_key"), cached);
}

const cache = (opts, c) => fs.readFileSync(path.join(opts.srv_root, c, "host_key"), "utf8");
const scanLine = (name, key) => `${name} ssh-rsa ${key}\n`;

// --- parsing / fingerprints -------------------------------------------------

test("parse_keyscan takes the first valid ssh-rsa line", () => {
  assert.equal(hk.parse_keyscan(""), undefined);
  assert.equal(hk.parse_keyscan(Buffer.from("")), undefined);
  assert.equal(hk.parse_keyscan("# c.test:22 SSH-2.0-OpenSSH_9.6\n"), undefined);
  assert.equal(hk.parse_keyscan(`c.test ssh-ed25519 ${A}\n`), undefined);
  assert.equal(hk.parse_keyscan("c.test ssh-rsa not-a-key\n"), undefined);
  assert.equal(hk.parse_keyscan("c.test ssh-rsa AAAA1\n"), undefined);
  assert.equal(hk.parse_keyscan(`c.test ssh-rsa ${A}`), A, "no final newline");
  assert.equal(hk.parse_keyscan(`# banner\r\nc.test ssh-rsa ${A}\r\n`), A, "CRLF + comment");
  assert.equal(hk.parse_keyscan(`c.test ssh-rsa ${A}\n10.1.2.3 ssh-rsa ${B}\n`), A, "two lines");
  assert.equal(hk.parse_keyscan(Buffer.from(`  c.test   ssh-rsa   ${B}  \n`)), B, "whitespace");
});

test("fingerprint matches ssh-keygen -lf when available", (root) => {
  const fp = hk.fingerprint(A);
  assert.match(fp, /^SHA256:[A-Za-z0-9+/]{43}$/);
  assert.notEqual(fp, hk.fingerprint(B));
  assert.equal(hk.fingerprint(undefined), "(none)");
  const file = path.join(root, "k.pub");
  fs.writeFileSync(file, `ssh-rsa ${A} test\n`);
  const r = spawnSync("ssh-keygen", ["-lf", file], { encoding: "utf8" });
  if (r.error || r.status !== 0) { console.log("      (ssh-keygen unavailable, cross-check skipped)"); return; }
  assert.equal(r.stdout.split(" ")[1], fp);
});

// --- containers ---------------------------------------------------------------

test("stale cached key of a running container is replaced everywhere and logged", (root) => {
  const { opts, log } = harness(root, { scans: { "c1.test": scanLine("c1.test", B) }, running: { "c1.test": true } });
  localContainer(opts, "c1.test", A);
  const containers = { "c1.test": { ip: "10.40.1.2", user: "u", host_key: A } };
  const hosts = { "h.test": { host_ip: "192.0.2.1", hostnet: 40, host_key: C } };

  assert.equal(hk.check_container_host_key(containers, "c1.test", opts), true);
  assert.equal(containers["c1.test"].host_key, B);
  assert.equal(cache(opts, "c1.test"), B);

  const kh = hk.render_known_hosts(hosts, containers, "srvctl-test", "h.test");
  for (const file of [kh.common, kh.host]) {
    assert.ok(file.includes(`c1.test ssh-rsa ${B}\n`));
    assert.ok(file.includes(`10.40.1.2 ssh-rsa ${B}\n`));
    assert.ok(!file.includes(A), "old key gone");
  }
  const changed = log.filter((l) => l.kind === "changed");
  assert.equal(changed.length, 1);
  assert.ok(changed[0].text.includes("c1.test"));
  assert.ok(changed[0].text.includes(hk.fingerprint(A)));
  assert.ok(changed[0].text.includes(hk.fingerprint(B)));
});

test("unchanged scanned key: no persist request, no message", (root) => {
  const { opts, calls, log } = harness(root, { scans: { "c1.test": scanLine("c1.test", A) }, running: { "c1.test": true } });
  localContainer(opts, "c1.test", A);
  const containers = { "c1.test": { ip: "10.40.1.2", host_key: A } };
  assert.equal(hk.check_container_host_key(containers, "c1.test", opts), false);
  assert.deepEqual(calls.scan, ["c1.test"]);
  assert.equal(containers["c1.test"].host_key, A);
  assert.equal(log.length, 0);
});

test("stopped container keeps its key and is not scanned", (root) => {
  const { opts, calls, log } = harness(root, { scans: { "c1.test": scanLine("c1.test", B) } });
  localContainer(opts, "c1.test", A);
  const containers = { "c1.test": { ip: "10.40.1.2", host_key: A } };
  assert.equal(hk.check_container_host_key(containers, "c1.test", opts), false);
  assert.deepEqual(calls.scan, []);
  assert.equal(containers["c1.test"].host_key, A);
  assert.equal(cache(opts, "c1.test"), A);
  assert.equal(log.length, 0);
});

test("empty, malformed or failing scans keep the existing key without throwing", (root) => {
  for (const out of ["", "# only a banner\n", "c1.test ssh-rsa AAAA1\nc1.test\n", new Error("boom")]) {
    const { opts } = harness(root, { scans: { "c1.test": out }, running: { "c1.test": true } });
    localContainer(opts, "c1.test", A);
    const containers = { "c1.test": { ip: "10.40.1.2", host_key: A } };
    assert.equal(hk.check_container_host_key(containers, "c1.test", opts), false);
    assert.equal(containers["c1.test"].host_key, A);
    assert.equal(cache(opts, "c1.test"), A);
    const kh = hk.render_known_hosts({}, containers, "srvctl-test", "h.test");
    assert.ok(kh.common.includes(`c1.test ssh-rsa ${A}\n`) && kh.host.includes(`10.40.1.2 ssh-rsa ${A}\n`));
  }
});

test("a failed scan next to another container's change keeps both keys in the saved map", (root) => {
  const { opts } = harness(root, {
    scans: { "c1.test": scanLine("c1.test", B), "c2.test": "" },
    running: { "c1.test": true, "c2.test": true },
  });
  localContainer(opts, "c1.test", A);
  localContainer(opts, "c2.test", C);
  const containers = { "c1.test": { ip: "10.40.1.2", host_key: A }, "c2.test": { ip: "10.40.1.3", host_key: C } };
  let write = false;
  for (const c of Object.keys(containers)) if (hk.check_container_host_key(containers, c, opts)) write = true;
  assert.equal(write, true);
  const saved = JSON.parse(JSON.stringify(containers)); // what save_type serialises
  assert.equal(saved["c1.test"].host_key, B);
  assert.equal(saved["c2.test"].host_key, C);
});

test("cache differing from the datastore no longer drops the key of a stopped container", (root) => {
  const { opts, calls } = harness(root);
  localContainer(opts, "c1.test", B);
  const containers = { "c1.test": { ip: "10.40.1.2", host_key: A } };
  assert.equal(hk.check_container_host_key(containers, "c1.test", opts), false);
  assert.deepEqual(calls.scan, []);
  assert.equal(containers["c1.test"].host_key, A);
  assert.equal(cache(opts, "c1.test"), A, "cache follows the key in use");
});

test("first discovery of a local container records the key and the cache", (root) => {
  const { opts, log } = harness(root, { scans: { "c1.test": scanLine("c1.test", B) } });
  localContainer(opts, "c1.test");
  const containers = { "c1.test": { ip: "10.40.1.2" } };
  assert.equal(hk.check_container_host_key(containers, "c1.test", opts), true, "scanned although not running: no key yet");
  assert.equal(containers["c1.test"].host_key, B);
  assert.equal(cache(opts, "c1.test"), B);
  assert.equal(log.filter((l) => l.kind === "new").length, 1);
});

test("missing datastore key with an unreachable container falls back to the cache file", (root) => {
  const { opts } = harness(root);
  localContainer(opts, "c1.test", A + "\n");
  const containers = { "c1.test": { ip: "10.40.1.2" } };
  assert.equal(hk.check_container_host_key(containers, "c1.test", opts), true);
  assert.equal(containers["c1.test"].host_key, A);
});

test("no key and no scan result: nothing is stored or written", (root) => {
  const { opts } = harness(root);
  localContainer(opts, "c1.test");
  const containers = { "c1.test": { ip: "10.40.1.2" } };
  assert.equal(hk.check_container_host_key(containers, "c1.test", opts), false);
  assert.equal("host_key" in containers["c1.test"], false);
  assert.equal(fs.existsSync(path.join(opts.srv_root, "c1.test", "host_key")), false);
  assert.equal(hk.render_known_hosts({}, containers, "srvctl-test", "h.test").common, "## srvctl-test generated\n");
});

test("containers hosted elsewhere: datastore key used as is, no cache write", (root) => {
  const { opts, calls } = harness(root, { scans: { "r1.test": scanLine("r1.test", B), "r2.test": scanLine("r2.test", B) } });
  const containers = { "r1.test": { ip: "10.41.1.2", host_key: A }, "r2.test": { ip: "10.41.1.3" } };
  assert.equal(hk.check_container_host_key(containers, "r1.test", opts), false);
  assert.equal(containers["r1.test"].host_key, A);
  assert.equal(hk.check_container_host_key(containers, "r2.test", opts), true, "first discovery still scans");
  assert.equal(containers["r2.test"].host_key, B);
  assert.deepEqual(calls.scan, ["r2.test"]);
  assert.equal(fs.existsSync(path.join(opts.srv_root, "r2.test")), false);
});

test("domain-only record (retire-ve): no scan, no cache write, not in known_hosts", (root) => {
  const { opts, calls } = harness(root, { scans: { "d1.test": scanLine("d1.test", B), "d2.test": scanLine("d2.test", B) } });
  localContainer(opts, "d1.test"); // a leftover /srv/d1.test
  const containers = {
    "d1.test": { ip: "10.40.1.2", host_key: A, domain_only: true },
    "d2.test": { ip: "10.40.1.3", domain_only: true },
  };
  assert.equal(hk.check_container_host_key(containers, "d1.test", opts), false);
  assert.equal(hk.check_container_host_key(containers, "d2.test", opts), false);
  assert.deepEqual(calls.scan, []);
  assert.equal(fs.existsSync(path.join(opts.srv_root, "d1.test", "host_key")), false);
  assert.equal("host_key" in containers["d2.test"], false);
  assert.equal(hk.render_known_hosts({}, containers, "srvctl-test", "h.test").common, "## srvctl-test generated\n");
});

// --- cluster hosts ---------------------------------------------------------------

test("cluster host with empty scan output: no save, no undefined key", (root) => {
  const { opts } = harness(root, { scans: { "h2.test": "" } });
  const hosts = { "h2.test": { host_ip: "192.0.2.2", hostnet: 41 } };
  assert.equal(hk.check_host_key(hosts, "h2.test", opts), false);
  assert.equal("host_key" in hosts["h2.test"], false);
  assert.ok(!JSON.stringify(hosts).includes("undefined"));
});

test("cluster host: existing key kept without scanning, missing key recorded", (root) => {
  const { opts, calls } = harness(root, { scans: { "h1.test": scanLine("h1.test", B), "h2.test": scanLine("h2.test", B) } });
  const hosts = { "h1.test": { host_key: A }, "h2.test": {} };
  assert.equal(hk.check_host_key(hosts, "h1.test", opts), false);
  assert.equal(hosts["h1.test"].host_key, A);
  assert.equal(hk.check_host_key(hosts, "h2.test", opts), true);
  assert.equal(hosts["h2.test"].host_key, B);
  assert.deepEqual(calls.scan, ["h2.test"]);
});

// --- rendering ---------------------------------------------------------------------

test("known_hosts line format is unchanged", () => {
  const hosts = { "h1.example": { host_ip: "192.0.2.1", hostnet: 40, host_key: "HK" }, "h2.example": { host_ip: "192.0.2.2", hostnet: 41 } };
  const containers = { "c.example": { ip: "10.40.1.2", host_key: "CK" }, "d.example": { ip: "10.40.1.3" } };
  const kh = hk.render_known_hosts(hosts, containers, "srvctl-4", "h1.example");
  const common =
    "## srvctl-4 generated\n" +
    "h1.example ssh-rsa HK\n192.0.2.1 ssh-rsa HK\nh1 ssh-rsa HK\n10.15.40.40 ssh-rsa HK\n\n" +
    "c.example ssh-rsa CK\n10.40.1.2 ssh-rsa CK\n\n";
  assert.equal(kh.common, common);
  assert.equal(kh.host, common + "localhost ssh-rsa HK\n127.0.0.1 ssh-rsa HK\n");
  assert.equal(hk.render_known_hosts(hosts, containers, "srvctl-4", "other").host, common);
});

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) process.exit(1);
