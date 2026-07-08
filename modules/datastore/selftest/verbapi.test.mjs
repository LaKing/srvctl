// modules/datastore/selftest/verbapi.test.mjs — GOLDEN-MASTER harness for the
// datastore verb API (modules/datastore/main.mjs).
//
// Purpose (WP-C precondition): freeze the EXACT output + exit-code + on-disk
// effect of the current (v3) verb API, so the v4 reimplementation can be
// proven byte-identical before any live path is replaced. ~159 call sites
// depend on this contract (see main.mjs header).
//
// Modes:
//   node verbapi.test.mjs --record   # run cases vs the live main.mjs, write golden.json
//   node verbapi.test.mjs            # VERIFY: run cases, diff against golden.json (exit!=0 on mismatch)
//
// Determinism: env is pinned (NOW/SC_HOSTNET/SC_COMPANY_DOMAIN/...); the one
// uncontrollable input is os.hostname() (lib.js reads it directly), so captured
// output has the live hostname normalized to "<HOST>". Each case runs against a
// FRESH copy of the fixture datastore, so mutating verbs are independent.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createStore } from "../lib/store.mjs";
import { migrateToPerEntity } from "../lib/migrate.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MAIN = path.join(HERE, "..", "main.mjs");
const FIXTURE = path.join(HERE, "golden", "fixture");
const GOLDEN_FILE = path.join(HERE, "golden", "golden.json");
const HOSTNAME = os.hostname();

const ENV = {
  ...process.env,
  SC_HOSTNET: "20",
  SC_USER: "root",
  USER: "root",
  NOW: "2026-01-01T00:00:00.000Z",
  SC_COMPANY_DOMAIN: "example.com",
  SRVCTL: "srvctl-4.0.0.2",
  SC_UID0: "true",
  SC_DATASTORE_RO: "", // exercise the (v3) writable path
};

// Normalize the machine hostname out of captured text so the golden is
// portable across machines (lib.js embeds os.hostname() in several outputs).
function norm(s) {
  if (typeof s !== "string") return s;
  let out = s.split(HOSTNAME).join("<HOST>");
  const short = HOSTNAME.split(".")[0];
  if (short && short !== HOSTNAME) out = out.split(short).join("<HOST>");
  return out;
}

// Each case: [name, argv[], mutating?]. Mutating cases also record the
// resulting datastore files. Read/derivation/out/error cases record stdout +
// stderr + exitCode only.
const CASES = [
  // ---- container: existence + plain + derivation GETs ----
  ["get-container-exist-true", ["get", "container", "site.example.com", "exist"]],
  ["get-container-exist-false", ["get", "container", "nope", "exist"]],
  ["get-container-user", ["get", "container", "site.example.com", "user"]],
  ["get-container-uid", ["get", "container", "site.example.com", "uid"]],
  ["get-container-br", ["get", "container", "site.example.com", "br"]],
  ["get-container-gw", ["get", "container", "site.example.com", "gw"]],
  ["get-container-interface", ["get", "container", "site.example.com", "interface"]],
  ["get-container-host", ["get", "container", "site.example.com", "host"]],
  ["get-container-host_ip", ["get", "container", "site.example.com", "host_ip"]],
  ["get-container-reseller", ["get", "container", "site.example.com", "reseller"]],
  ["get-container-http_port", ["get", "container", "site.example.com", "http_port"]],
  ["get-container-hostnet", ["get", "container", "site.example.com", "hostnet"]],
  ["get-container-undefined-field", ["get", "container", "site.example.com", "no_such_field"]],
  ["get-container-missing", ["get", "container", "ghost.example.com", "user"]],
  // ---- container: text generators (multi-line) ----
  ["get-container-domains", ["get", "container", "shop.example.com", "domains"]],
  ["get-container-hosts", ["get", "container", "site.example.com", "hosts"]],
  // Deliberately not covered here: resolv_conf. v3 hardcodes os.hostname()
  // and dereferences hosts[HOSTNAME], so a portable fixture whose host list
  // does not include the test machine pins a fixture crash, not a live
  // contract. Cover it in derivation/generator tests with explicit HOSTNAME.
  // ---- container: cfg mutators and errors ----
  ["cfg-container-update_ip", ["cfg", "container", "shop.example.com", "update_ip"], true],
  ["cfg-container-add_mapped_port", ["cfg", "container", "site.example.com", "add_mapped_port", "udp", "22", "ssh access"], true],
  ["cfg-container-invalid", ["cfg", "container", "site.example.com", "no_such_cfg"]],
  // ---- container: out formats ----
  ["out-container", ["out", "container", "site.example.com"]],
  ["out-container-aliases", ["out", "container", "shop.example.com"]],
  ["out-container-json", ["out", "container", "site.example.com", "json"]],
  // ---- container: new ----
  ["new-container", ["new", "container", "newsite.example.com", "fedora"], true],
  ["new-container-bridge", ["new", "container", "bridged.example.com", "fedora", "br-test"], true],
  // ---- user ----
  ["get-user-exist-true", ["get", "user", "alice", "exist"]],
  ["get-user-exist-false", ["get", "user", "nobody", "exist"]],
  ["get-user-uid", ["get", "user", "alice", "uid"]],
  ["get-user-undefined-field", ["get", "user", "alice", "reseller"]],
  ["out-user", ["out", "user", "alice"]],
  ["cfg-user-container_list", ["cfg", "user", "container_list"]],
  ["get-user-missing", ["get", "user", "nobody", "name"]],
  // WP-F Phase 1 DIVERGENCE from v3: `new user` no longer stamps user.reseller
  // (and no longer requires the actor to be a reseller). The golden new-user
  // case was updated to drop carol's reseller field; everything else stays
  // byte/semantic-exact against v3. `new reseller` is untouched until a later
  // WP-F phase removes the reseller layer entirely.
  ["new-user", ["new", "user", "carol"], true],
  ["new-reseller", ["new", "reseller", "agency"], true],
  // ---- host ----
  ["get-host-host_ip", ["get", "host", "node1", "host_ip"]],
  ["get-host-hostnet", ["get", "host", "node1", "hostnet"]],
  ["out-host", ["out", "host", "node1"]],
  ["get-host-missing", ["get", "host", "node9", "host_ip"]],
  // ---- cluster ----
  ["get-cluster-host_list", ["get", "cluster", "host_list"]],
  ["get-cluster-host_ip_list", ["get", "cluster", "host_ip_list"]],
  ["get-cluster-user_list", ["get", "cluster", "user_list"]],
  ["get-cluster-container_list", ["get", "cluster", "container_list"]],
  ["get-cluster-etc_hosts", ["get", "cluster", "etc_hosts"]],
  ["get-cluster-postfix_relaydomains", ["get", "cluster", "postfix_relaydomains"]],
  ["get-cluster-host_keys", ["get", "cluster", "host_keys"]],
  ["get-cluster-unknown", ["get", "cluster", "no_such_cluster_fn"]],
  ["out-cluster-unsupported", ["out", "cluster", "host_list"]],
  // ---- argument / dispatch errors ----
  ["err-no-args", []],
  ["err-missing-dat", ["get"]],
  ["err-missing-arg", ["get", "container"]],
  ["err-invalid-cmd", ["frob", "container", "site.example.com"]],
  ["err-invalid-dat", ["get", "widget", "x"]],
  // ---- mutations (record resulting files too) ----
  ["put-container-field", ["put", "container", "site.example.com", "note", "hello world"], true],
  ["put-container-bool", ["put", "container", "site.example.com", "is_mail", "true"], true],
  ["put-container-delete-field", ["put", "container", "shop.example.com", "aliases"], true],
  ["del-container", ["del", "container", "mail.site.example.com"], true],
  ["add-container-user", ["add", "container", "site.example.com", "user", "carol"], true],
  ["add-container-vncuser", ["add", "container", "site.example.com", "vncuser", "viewer"], true],
  ["put-user-field", ["put", "user", "alice", "note", "vip"], true],
  ["put-user-bool", ["put", "user", "alice", "active", "false"], true],
  ["put-user-delete-field", ["put", "user", "bob", "reseller"], true],
  ["del-user", ["del", "user", "bob"], true],
];

// WP-C step 2: main.mjs reads/writes file-per-entity. Migrate the monolithic
// fixture into a per-entity store so each case runs against the new backend.
function freshDatastore() {
  const src = fs.mkdtempSync(path.join(os.tmpdir(), "sc-mono-"));
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sc-verbapi-"));
  for (const f of ["hosts.json", "users.json", "containers.json"]) {
    fs.copyFileSync(path.join(FIXTURE, f), path.join(src, f));
  }
  migrateToPerEntity(src, createStore(dir, { git: false }));
  fs.rmSync(src, { recursive: true, force: true });
  return dir;
}

function runCase([name, argv, mutating]) {
  const dir = freshDatastore();
  try {
    const r = spawnSync(process.execPath, [MAIN, ...argv], {
      env: { ...ENV, SC_DATASTORE_DIR: dir },
      encoding: "utf8",
    });
    if (r.error) {
      throw new Error(`spawn main.mjs for ${name}: ${r.error.message}`);
    }
    const record = {
      argv,
      stdout: norm(r.stdout),
      stderr: norm(r.stderr),
      exitCode: r.status,
    };
    if (mutating) {
      // Storage is file-per-entity now, so compare the resulting SEMANTIC
      // state (the entity maps) rather than raw monolithic file bytes. The
      // stdout/stderr/exit contract stays byte-exact against the v3 golden.
      const s = createStore(dir, { git: false });
      record.files = {
        "hosts.json": s.readAll("hosts"),
        "users.json": s.readAll("users"),
        "containers.json": s.readAll("containers"),
      };
    }
    return record;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const record = process.argv.includes("--record");
const results = {};
for (const c of CASES) results[c[0]] = runCase(c);

if (record) {
  fs.writeFileSync(GOLDEN_FILE, JSON.stringify(results, null, 2) + "\n");
  console.log(`recorded ${CASES.length} cases → ${path.relative(process.cwd(), GOLDEN_FILE)}`);
  process.exit(0);
}

// VERIFY
if (!fs.existsSync(GOLDEN_FILE)) {
  console.error("no golden.json — run: node verbapi.test.mjs --record");
  process.exit(2);
}
const golden = JSON.parse(fs.readFileSync(GOLDEN_FILE, "utf8"));

// stdout/stderr/exit are compared BYTE-EXACT (the v3 contract). Mutation
// file-effects are compared SEMANTICALLY (entity maps, order-independent),
// since per-entity storage decouples byte layout from the data. The frozen v3
// golden stores files as monolithic JSON strings; a re-recorded step-2 golden
// stores them as maps — handle both. (Record-level field order within a stored
// entity is guarded separately by the frozen mutator golden.)
function eqJson(a, b) { try { assert.deepEqual(a, b); return true; } catch { return false; } }
function sameRecord(got, want) {
  if (got.stdout !== want.stdout || got.stderr !== want.stderr || got.exitCode !== want.exitCode) return false;
  if (Boolean(got.files) !== Boolean(want.files)) return false;
  if (want.files) {
    for (const k of Object.keys(want.files)) {
      const wantMap = typeof want.files[k] === "string" ? JSON.parse(want.files[k]) : want.files[k];
      if (!eqJson(got.files[k], wantMap)) return false;
    }
  }
  return true;
}
let passed = 0;
const failures = [];
for (const c of CASES) {
  const name = c[0];
  if (sameRecord(results[name], golden[name])) passed++;
  else failures.push({ name, got: results[name], want: golden[name] });
}
// A golden entry with no matching case (removed case) is also drift.
for (const name of Object.keys(golden)) {
  if (!CASES.find((c) => c[0] === name)) failures.push({ name, got: "(case removed)", want: golden[name] });
}

console.log(`verbapi.test: ${passed}/${CASES.length} match golden, ${failures.length} failed`);
for (const f of failures) {
  console.log(`  FAIL ${f.name}`);
  console.log(`    want: ${JSON.stringify(f.want)}`);
  console.log(`    got:  ${JSON.stringify(f.got)}`);
}
process.exit(failures.length ? 1 : 0);
