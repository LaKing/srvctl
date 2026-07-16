// modules/datastore/selftest/mutators.test.mjs — golden test for the v4 pure
// mutators (mutators.mjs) against a frozen v3 capture.
//
// Group A (golden): compare pure mutators against checked-in v3 resulting
//   records captured via capture-mutators.cjs over a fixture. Covers new_user,
//   new_reseller, new_container (plain + bridge), container_update_ip.
// Group B (v4-only): container_add_mapped_port allocation logic (the argv
//   juggling + end-to-end is covered by the verb golden's
//   cfg-container-add_mapped_port case).
//
// Run: node modules/datastore/selftest/mutators.test.mjs  (exit != 0 on fail)
// Re-record while v3 lib.js still exists:
//      node modules/datastore/selftest/mutators.test.mjs --record
//
// NOTE: --record depends on modules/datastore/lib.js. Normal verification does
// not, so WP-C can replace lib.js after this golden exists.

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
const GOLDEN_FILE = path.join(HERE, "golden", "mutators.json");
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
    const clustersFile = path.join(dir, "cluster-topology.fixture.json");
    fs.writeFileSync(clustersFile, JSON.stringify({ test_cluster: {
      n1: { hostnet: 20, host_ip: "10.16.20.1" },
    } }));
    const r = spawnSync(process.execPath, [CAPTURE, op, ...args], {
      env: {
        ...ENV,
        SC_DATASTORE_DIR: dir,
        SRVCTL_SELFTEST: "true",
        SRVCTL_SELFTEST_CLUSTERS_FILE: clustersFile,
        SRVCTL_SELFTEST_HOSTNAME: "n1",
      },
      encoding: "utf8",
    });
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

function captureV3Golden() {
  return {
    // new_user is a WP-F Phase 1 v4 DIVERGENCE (no reseller) — asserted
    // explicitly below, NOT captured from the v3 oracle (which stamps reseller
    // and requires the actor to be a reseller).
    new_reseller: v3("new_reseller", "agency"),
    new_container: v3("new_container", "new.example.com", "fedora"),
    "new_container bridge": v3("new_container", "bridged.example.com", "fedora", "br-test"),
    update_ip: v3("update_ip", "shop.example.com"),
  };
}

// ---- Group A: checked-in v3 capture ---------------------------------------

{
  const record = process.argv.includes("--record");
  if (record) {
    const captured = captureV3Golden();
    fs.mkdirSync(path.dirname(GOLDEN_FILE), { recursive: true });
    fs.writeFileSync(GOLDEN_FILE, JSON.stringify(captured, null, 2) + "\n");
    console.log(`recorded ${Object.keys(captured).length} mutator entries -> ${path.relative(process.cwd(), GOLDEN_FILE)}`);
  }
  if (!fs.existsSync(GOLDEN_FILE)) {
    throw new Error("missing mutator golden; run mutators.test.mjs --record while v3 lib.js exists");
  }
  const v3Golden = JSON.parse(fs.readFileSync(GOLDEN_FILE, "utf8"));
  // WP-F Phase 1: new_user DIVERGES from v3 — no reseller_id requirement, no
  // user.reseller stamp. Asserted explicitly (not against the v3 oracle).
  check("new_user v4 (root, no reseller)", newUser(freshState(), "carol", { SC_USER: "root", NOW }),
    { added_by_username: "root", added_on_datestamp: NOW, user_id: 3, uid: 1003 });
  // a NON-reseller actor (bob has no reseller_id) may now create users — v3 threw.
  check("new_user v4 (non-reseller actor allowed)", newUser(freshState(), "dave", { SC_USER: "bob", NOW }),
    { added_by_username: "bob", added_on_datestamp: NOW, user_id: 3, uid: 1003 });
  check("new_reseller", newReseller(freshState(), "agency", { SC_USER: "root", NOW }), v3Golden.new_reseller);
  check("new_container", newContainer(freshState(), "new.example.com", "fedora", undefined, { SC_USER: "root", NOW, SC_HOSTNET: "20" }), v3Golden.new_container);
  check("new_container bridge", newContainer(freshState(), "bridged.example.com", "fedora", "br-test", { SC_USER: "root", NOW, SC_HOSTNET: "20" }), v3Golden["new_container bridge"]);
  check("update_ip", containerUpdateIp(freshState(), "shop.example.com", { SC_HOSTNET: "20" }), v3Golden.update_ip);
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
