// modules/datastore/selftest/store.test.mjs — selftest for the v4 datastore
// storage engine (store.mjs) and migrator (migrate.mjs). Zero dependencies;
// run with:  node modules/datastore/selftest/store.test.mjs
// Exits non-zero on any failure (usable as a CI/verify gate).

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { createStore, StoreError } from "../lib/store.mjs";
import { migrateToPerEntity, exportToMonolithic } from "../lib/migrate.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const STORE_MJS = path.join(HERE, "..", "lib", "store.mjs");
const DEFAULT_USERS = path.join(HERE, "..", "default-users.json");

let passed = 0;
const failures = [];
function test(name, fn) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sc-store-"));
  try {
    fn(tmp);
    passed++;
    console.log(`  ok  ${name}`);
  } catch (err) {
    failures.push({ name, err });
    console.log(`FAIL  ${name}\n      ${err.stack || err}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// ---- basics: write / read / has / list / delete ---------------------------

test("write/read round-trips a record", (dir) => {
  const s = createStore(dir, { git: false });
  const rec = { user: "alice", ip: "10.16.20.5", nested: { a: 1, b: [2, 3] } };
  s.write("containers", "site.example.com", rec);
  assert.deepEqual(s.read("containers", "site.example.com"), rec);
  assert.equal(s.has("containers", "site.example.com"), true);
  assert.equal(s.read("containers", "nope"), null);
  assert.equal(s.has("containers", "nope"), false);
});

test("list returns sorted ids, delete removes", (dir) => {
  const s = createStore(dir, { git: false });
  s.write("users", "bob", { name: "Bob" });
  s.write("users", "alice", { name: "Alice" });
  assert.deepEqual(s.list("users"), ["alice", "bob"]);
  assert.equal(s.remove("users", "bob"), true);
  assert.equal(s.remove("users", "bob"), false); // idempotent
  assert.deepEqual(s.list("users"), ["alice"]);
  assert.deepEqual(s.list("nonexistent-type-dir".replace(/-/g, "")), []);
});

test("on-disk file is human-readable 2-space JSON with trailing newline", (dir) => {
  const s = createStore(dir, { git: false });
  s.write("hosts", "node1", { hostnet: 20, host_ip: "1.2.3.4" });
  const raw = fs.readFileSync(path.join(dir, "hosts", "node1.json"), "utf8");
  assert.equal(raw, '{\n  "hostnet": 20,\n  "host_ip": "1.2.3.4"\n}\n');
});

// ---- validation -----------------------------------------------------------

test("validator rejects a bad record and preserves the old file", (dir) => {
  const validators = {
    users: (rec) => {
      if (typeof rec.uid !== "number") throw new StoreError("SCHEMA", "uid must be a number");
    },
  };
  const s = createStore(dir, { git: false, validators });
  s.write("users", "alice", { uid: 1001, name: "Alice" });
  assert.throws(() => s.write("users", "alice", { uid: "oops" }), /uid must be a number/);
  // old file intact
  assert.deepEqual(s.read("users", "alice"), { uid: 1001, name: "Alice" });
});

test("unsafe ids and types are rejected", (dir) => {
  const s = createStore(dir, { git: false });
  for (const bad of ["../etc/passwd", "a/b", "..", ".hidden", "", "a b"]) {
    assert.throws(() => s.write("containers", bad, {}), StoreError, `id ${JSON.stringify(bad)}`);
  }
  assert.throws(() => s.write("Bad-Type", "x", {}), StoreError);
});

// ---- atomicity ------------------------------------------------------------

test("no temp files leak after a write", (dir) => {
  const s = createStore(dir, { git: false });
  s.write("containers", "c1", { a: 1 });
  const leftovers = fs.readdirSync(path.join(dir, "containers")).filter((n) => n.includes(".tmp"));
  assert.deepEqual(leftovers, []);
});

// ---- read-only guard (fixes v3's dead guard) ------------------------------

test("readOnly store refuses writes", (dir) => {
  const rw = createStore(dir, { git: false });
  rw.write("users", "alice", { uid: 1 });
  const ro = createStore(dir, { git: false, readOnly: true });
  assert.equal(ro.read("users", "alice").uid, 1); // reads OK
  assert.throws(() => ro.write("users", "alice", { uid: 2 }), /read-only/);
  assert.throws(() => ro.remove("users", "alice"), /read-only/);
});

// ---- locking: stale steal + contended timeout -----------------------------

test("a stale lock is stolen; a fresh lock times out", (dir) => {
  fs.mkdirSync(dir, { recursive: true });
  const lock = path.join(dir, ".lock");

  // Fresh lock held by "someone else": write times out fast.
  fs.writeFileSync(lock, "99999 held\n");
  const s = createStore(dir, { git: false, lockWaitMs: 120, lockStaleMs: 60_000, lockPollMs: 10 });
  assert.throws(() => s.write("users", "x", { a: 1 }), (e) => e instanceof StoreError && e.code === "LOCK-TIMEOUT");

  // Make the same lock look stale (mtime far in the past): write steals it.
  const past = new Date(Date.now() - 10 * 60_000);
  fs.utimesSync(lock, past, past);
  s.write("users", "x", { a: 1 });
  assert.deepEqual(s.read("users", "x"), { a: 1 });
});

// ---- cross-process concurrency (the real fragility v3 had) ----------------

test("concurrent writes from two processes to different entities both land", (dir) => {
  // Two child node processes each write a different container 20× through the
  // engine, at the same time. v3 lost updates here (whole-file rewrite of a
  // start-of-process snapshot); file-per-entity + the cross-process lock must
  // let both survive with their final values.
  const child = (id) =>
    `import { createStore } from ${JSON.stringify(STORE_MJS)};` +
    `const s = createStore(${JSON.stringify(dir)}, { git: false, lockWaitMs: 8000, lockPollMs: 5 });` +
    `for (let i=0;i<20;i++) s.write("containers", ${JSON.stringify(id)}, { id: ${JSON.stringify(id)}, i });`;
  spawnNodeParallel([child("alpha.example.com"), child("bravo.example.com")]);

  const s = createStore(dir, { git: false });
  assert.deepEqual(s.list("containers"), ["alpha.example.com", "bravo.example.com"]);
  assert.equal(s.read("containers", "alpha.example.com").i, 19);
  assert.equal(s.read("containers", "bravo.example.com").i, 19);
});

// Launch several node module snippets in parallel (bash background + wait),
// so they genuinely overlap; throws if any child exits non-zero.
function spawnNodeParallel(codes) {
  const files = codes.map((c, i) => {
    const f = path.join(os.tmpdir(), `sc-child-${process.pid}-${i}.mjs`);
    fs.writeFileSync(f, c);
    return f;
  });
  const shell = files.map((f) => `"${process.execPath}" "${f}" &`).join(" ") + " wait";
  try {
    execFileSync("bash", ["-c", shell], { stdio: "inherit" });
  } finally {
    for (const f of files) { try { fs.unlinkSync(f); } catch { /* ignore */ } }
  }
}

// ---- migration round-trip (lossless) --------------------------------------

test("migrate monolithic → per-entity is lossless (round-trip)", (dir) => {
  const src = path.join(dir, "src");
  const dst = path.join(dir, "store");
  fs.mkdirSync(src, { recursive: true });

  const hosts = { node1: { hostnet: 20, host_ip: "10.16.20.1" }, node2: { hostnet: 21, host_ip: "10.16.21.1" } };
  const users = JSON.parse(fs.readFileSync(DEFAULT_USERS, "utf8"));
  const containers = {
    "site.example.com": { user: "a", ip: "10.16.20.5", users: ["a", "b"], mapped_ports: [] },
    "mail.example.com": { user: "b", ip: "10.16.20.6", vncusers: [] },
  };
  fs.writeFileSync(path.join(src, "hosts.json"), JSON.stringify(hosts, null, 2));
  fs.writeFileSync(path.join(src, "users.json"), JSON.stringify(users, null, 2));
  fs.writeFileSync(path.join(src, "containers.json"), JSON.stringify(containers, null, 2));

  const store = createStore(dst, { git: false });
  const counts = migrateToPerEntity(src, store);
  assert.equal(counts.hosts, 2);
  assert.equal(counts.users, Object.keys(users).length);
  assert.equal(counts.containers, 2);

  const back = exportToMonolithic(store);
  assert.deepEqual(back.hosts, hosts);
  assert.deepEqual(back.users, users);
  assert.deepEqual(back.containers, containers);
});

test("migrate tolerates a missing optional file, requires hosts.json", (dir) => {
  const src = path.join(dir, "src");
  fs.mkdirSync(src, { recursive: true });
  fs.writeFileSync(path.join(src, "hosts.json"), JSON.stringify({ n1: { hostnet: 1 } }));
  // no users.json / containers.json
  const store = createStore(path.join(dir, "store"), { git: false });
  const counts = migrateToPerEntity(src, store);
  assert.deepEqual(counts, { hosts: 1, users: 0, containers: 0 });

  const src2 = path.join(dir, "src2");
  fs.mkdirSync(src2, { recursive: true });
  assert.throws(() => migrateToPerEntity(src2, createStore(path.join(dir, "s2"), { git: false })), /required/);
});

// ---- git versioning -------------------------------------------------------

test("git mode records a commit per change", (dir) => {
  const s = createStore(dir, { git: true });
  s.write("users", "alice", { uid: 1 });
  s.write("users", "alice", { uid: 2 });
  s.remove("users", "alice");
  const log = execFileSync("git", ["-C", dir, "log", "--oneline"], { encoding: "utf8" }).trim().split("\n");
  assert.ok(log.length >= 3, `expected >=3 commits, got ${log.length}`);
  assert.match(log[0], /delete users\/alice/);
});

// ---------------------------------------------------------------------------

console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
