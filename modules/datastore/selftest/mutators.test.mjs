// modules/datastore/selftest/mutators.test.mjs — differential test for the v4
// pure mutators (mutators.mjs) against the live v3 lib.js.
//
// Group A (differential): for each mutation, capture v3's resulting record via
//   capture-mutators.cjs over a fixture, apply the v4 pure mutator to the same
//   state, assert deep-equal. Covers new_user, new_reseller, new_container
//   (plain + bridge), container_update_ip.
// Group B (v4-only): container_add_mapped_port allocation logic (the argv
//   juggling + end-to-end is covered by the verb golden's
//   cfg-container-add_mapped_port case).
//
// Run: node modules/datastore/selftest/mutators.test.mjs  (exit != 0 on fail)
// NB: Group A is a LIVE DIFFERENTIAL against v3 lib.js (present until WP-C
// cutover). The verb golden already freezes the same mutations end-to-end.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import {
  newUser, newReseller, newContainer, containerUpdateIp, containerAddMappedPort,
} from "../lib/mutators.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CAPTURE = path.join(HERE, "capture-mutators.cjs");
const NOW = "2026-01-01T00:00:00.000Z";

const USERS = {
  root: { reseller_id: 0, user_id: 0, uid: 0, name: "root" },
  alice: { reseller_id: 1, user_id: 1, uid: 1001, name: "Alice" },
  bob: { user_id: 2, uid: 1002, reseller: "alice", name: "Bob" },
};
const CONTAINERS = {
  "site.example.com": { user: "alice", ip: "10.20.1.5" },
  "shop.example.com": { user: "bob", ip: "10.20.2.6" },
  "mail.site.example.com": { user: "alice", ip: "10.20.1.9" },
};
const ENV = {
  ...process.env,
  SC_HOSTNET: "20", SC_USER: "root", USER: "root", NOW,
  SC_COMPANY_DOMAIN: "example.com", SRVCTL: "srvctl-4.0.0.2",
};

let passed = 0;
const failures = [];
function check(name, got, want) {
  try { assert.deepEqual(got, want); passed++; }
  catch { failures.push({ name, got, want }); }
}

// Run v3 capture for one mutation against a fresh fixture; return parsed result.
function v3(op, ...args) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sc-mut-"));
  try {
    fs.writeFileSync(path.join(dir, "hosts.json"), JSON.stringify({ n1: { hostnet: 20, host_ip: "10.16.20.1" } }));
    fs.writeFileSync(path.join(dir, "users.json"), JSON.stringify(USERS));
    fs.writeFileSync(path.join(dir, "containers.json"), JSON.stringify(CONTAINERS));
    const r = spawnSync(process.execPath, [CAPTURE, op, ...args], { env: { ...ENV, SC_DATASTORE_DIR: dir }, encoding: "utf8" });
    if (r.error) throw new Error(`spawn capture: ${r.error.message}`);
    if (r.status !== 0) throw new Error(`capture ${op} exited ${r.status}: ${r.stderr}`);
    const line = r.stdout.split("\n").filter(Boolean).find((l) => l.startsWith("@@RESULT@@"));
    if (!line) throw new Error(`no @@RESULT@@ line for ${op}: ${JSON.stringify(r.stdout)}`);
    return JSON.parse(line.slice("@@RESULT@@".length));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const freshState = () => ({ users: structuredClone(USERS), containers: structuredClone(CONTAINERS) });

// ---- Group A: differential vs live v3 -------------------------------------
// Skipped once WP-C removes lib.js — the verb golden then covers these
// mutations end-to-end (new-user/new-reseller/new-container/cfg-update_ip).

if (fs.existsSync(path.join(HERE, "..", "lib.js"))) {
  check("new_user", newUser(freshState(), "carol", { SC_USER: "root", NOW }), v3("new_user", "carol"));
  check("new_reseller", newReseller(freshState(), "agency", { SC_USER: "root", NOW }), v3("new_reseller", "agency"));
  check("new_container", newContainer(freshState(), "new.example.com", "fedora", undefined, { SC_USER: "root", NOW, SC_HOSTNET: "20" }), v3("new_container", "new.example.com", "fedora"));
  check("new_container bridge", newContainer(freshState(), "bridged.example.com", "fedora", "br-test", { SC_USER: "root", NOW, SC_HOSTNET: "20" }), v3("new_container", "bridged.example.com", "fedora", "br-test"));
  check("update_ip", containerUpdateIp(freshState(), "shop.example.com", { SC_HOSTNET: "20" }), v3("update_ip", "shop.example.com"));
} else {
  console.log("  SKIP Group A differential (lib.js absent — verb golden covers mutations)");
}

// ---- Group B: add_mapped_port allocation (v4-only) ------------------------

{
  // container_port 22 with the v3 ladder: 22 -> 2000+22 = 2022, free -> host_port 2022.
  const entry = containerAddMappedPort(freshState(), "site.example.com",
    { proto: "udp", container_port: 22, comment: "22 ssh access", SC_USER: "root", NOW });
  check("add_mapped_port entry", entry,
    { proto: "udp", comment: "22 ssh access", container_port: 22, user: "root", timestamp: NOW, host_port: 2022 });

  // Collision: an existing tcp:2022 pushes the next allocation to 2023.
  const st = freshState();
  st.containers["site.example.com"].mapped_ports = [{ proto: "udp", host_port: 2022, container_port: 22 }];
  const entry2 = containerAddMappedPort(st, "site.example.com",
    { proto: "udp", container_port: 22, comment: "x", SC_USER: "root", NOW });
  check("add_mapped_port collision -> 2023", entry2.host_port, 2023);

  // Invalid port throws.
  let threw = false;
  try { containerAddMappedPort(freshState(), "site.example.com", { proto: "tcp", container_port: 99999, comment: "x", SC_USER: "root", NOW }); }
  catch { threw = true; }
  check("add_mapped_port invalid throws", threw, true);
}

console.log(`mutators.test: ${passed} passed, ${failures.length} failed`);
for (const f of failures) {
  console.log(`  FAIL ${f.name}`);
  console.log(`    want (v3): ${JSON.stringify(f.want)}`);
  console.log(`    got  (v4): ${JSON.stringify(f.got)}`);
}
process.exit(failures.length ? 1 : 0);
