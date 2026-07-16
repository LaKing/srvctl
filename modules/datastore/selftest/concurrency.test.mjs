// modules/datastore/selftest/concurrency.test.mjs — verb-level concurrency
// tests for the datastore mutating verbs. Reproduces the read-modify-write
// race (Codex finding) and proves it is fixed: each mutating verb now runs its
// fresh read + allocation + write inside one store.transaction() lock, so
// concurrent allocations cannot collide.
//
// Run: node modules/datastore/selftest/concurrency.test.mjs  (exit != 0 on fail)

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { createStore } from "../lib/store.mjs";
import { migrateToPerEntity } from "../lib/migrate.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MAIN = path.join(HERE, "..", "main.mjs");
const CLUSTERS = path.join(HERE, "golden", "fixture", "cluster-topology.fixture.json");
const N = 20;

let passed = 0;
const failures = [];
function ok(name, cond, detail = "") {
  if (cond) { passed++; console.log(`  ok  ${name}`); }
  else { failures.push(`${name}${detail ? " — " + detail : ""}`); console.log(`FAIL  ${name} ${detail}`); }
}

// Build a fresh per-entity store from inline monolithic fixtures.
function setup(hosts, users, containers) {
  const src = fs.mkdtempSync(path.join(os.tmpdir(), "sc-cc-src-"));
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sc-cc-"));
  fs.writeFileSync(path.join(src, "hosts.json"), JSON.stringify(hosts));
  fs.writeFileSync(path.join(src, "users.json"), JSON.stringify(users));
  fs.writeFileSync(path.join(src, "containers.json"), JSON.stringify(containers));
  migrateToPerEntity(src, createStore(dir, { git: false }));
  fs.rmSync(src, { recursive: true, force: true });
  return dir;
}

// Launch `node main.mjs <argv>` for every argv IN PARALLEL against `dir`, wait
// for all. Uses bash background + wait so they genuinely overlap and contend.
function parallel(dir, argvList, env) {
  const base = { ...process.env, ...env, SC_DATASTORE_DIR: dir };
  const q = (s) => `'${String(s).replace(/'/g, "'\\''")}'`;
  const script = argvList.map((argv) => {
    const envStr = Object.entries(base).map(([k, v]) => `${k}=${q(v)}`).join(" ");
    const argStr = argv.map(q).join(" ");
    return `${envStr} ${q(process.execPath)} ${q(MAIN)} ${argStr} >/dev/null 2>&1 &`;
  }).join("\n") + "\nwait\n";
  execFileSync("bash", ["-c", script], { stdio: "ignore" });
}

const ENV = {
  SC_HOSTNET: "20", SC_USER: "root", USER: "root",
  NOW: "2026-01-01T00:00:00.000Z", SC_COMPANY_DOMAIN: "example.com",
  SRVCTL_SELFTEST: "true",
  SRVCTL_SELFTEST_CLUSTERS_FILE: CLUSTERS,
  SRVCTL_SELFTEST_HOSTNAME: "node1",
};
const HOSTS = { node1: { hostnet: 20, host_ip: "10.16.20.1" } };
const USERS = { root: { reseller_id: 0, user_id: 0, uid: 0, name: "root" } };

// ---- new container: no duplicate IPs --------------------------------------
{
  const dir = setup(HOSTS, USERS, {});
  const names = Array.from({ length: N }, (_, i) => `race-${i}.example.com`);
  parallel(dir, names.map((n) => ["new", "container", n, "fedora"]), ENV);
  const c = createStore(dir, { git: false }).readAll("containers");
  const ids = Object.keys(c);
  const ips = ids.map((k) => c[k].ip);
  ok("new container: all N created", ids.length === N, `got ${ids.length}`);
  ok("new container: no duplicate IPs", new Set(ips).size === ips.length, `${ips.length - new Set(ips).size} dup(s): ${dupsOf(ips)}`);
  fs.rmSync(dir, { recursive: true, force: true });
}

// ---- new user: no duplicate user_id / uid ---------------------------------
{
  const dir = setup(HOSTS, USERS, {});
  const names = Array.from({ length: N }, (_, i) => `user${i}`);
  parallel(dir, names.map((n) => ["new", "user", n]), ENV);
  const u = createStore(dir, { git: false }).readAll("users");
  const created = Object.keys(u).filter((k) => k !== "root");
  const uids = created.map((k) => u[k].user_id);
  const sysuids = created.map((k) => u[k].uid);
  ok("new user: all N created", created.length === N, `got ${created.length}`);
  ok("new user: no duplicate user_id", new Set(uids).size === uids.length, `dups: ${dupsOf(uids)}`);
  ok("new user: no duplicate uid", new Set(sysuids).size === sysuids.length, `dups: ${dupsOf(sysuids)}`);
  fs.rmSync(dir, { recursive: true, force: true });
}

// ---- cfg add_mapped_port: no duplicate host_port on one container ---------
{
  const dir = setup(HOSTS, USERS, { "svc.example.com": { user: "root", ip: "10.20.0.5" } });
  parallel(dir, Array.from({ length: N }, (_, i) => ["cfg", "container", "svc.example.com", "add_mapped_port", "tcp", "22", `c${i}`]), ENV);
  const c = createStore(dir, { git: false }).readAll("containers");
  const ports = (c["svc.example.com"].mapped_ports || []).map((p) => p.host_port);
  ok("add_mapped_port: all N appended", ports.length === N, `got ${ports.length}`);
  ok("add_mapped_port: no duplicate host_port", new Set(ports).size === ports.length, `dups: ${dupsOf(ports)}`);
  fs.rmSync(dir, { recursive: true, force: true });
}

function dupsOf(arr) {
  const seen = new Set(), dup = new Set();
  for (const x of arr) { if (seen.has(x)) dup.add(x); seen.add(x); }
  return [...dup].join(",");
}

console.log(`\nconcurrency.test: ${passed} passed, ${failures.length} failed`);
for (const f of failures) console.log("  FAIL " + f);
process.exit(failures.length ? 1 : 0);
