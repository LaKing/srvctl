// update-campaign/wpf-phase0-inventory.test.mjs — tests for the Phase 0
// reseller inventory. Covers BOTH datastore layouts (v3 monolithic, v4 flat
// per-entity) and all three reseller-key filename variants.
//
// Run: node update-campaign/wpf-phase0-inventory.test.mjs   (exit != 0 on fail)

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { loadMap, classify, scanResellerKeys, RESELLER_KEY_RE } from "./wpf-phase0-inventory.mjs";

let pass = 0;
const fails = [];
const eq = (name, got, want) => {
  if (JSON.stringify(got) === JSON.stringify(want)) pass++;
  else fails.push({ name, got, want });
};

// A shared reseller shape: alice = real reseller; bob tied to alice; seed 'a'
// ACTIVE (owns a user + a container); seed 'b' vestigial; root.
const USERS = {
  root: { reseller_id: 0 },
  alice: { reseller_id: 1, reseller: "alice" },
  bob: { reseller: "alice" },
  a: { reseller_id: 1001, reseller: "a" }, // seed, ACTIVE below
  seeduser: { reseller: "a" },
  b: { reseller_id: 1002, reseller: "b" }, // seed, vestigial
};
const CONTAINERS = {
  bobsite: { user: "bob" },
  alicesite: { user: "alice" },
  aseedsite: { user: "a" },
};

function writeMono(dir) {
  fs.writeFileSync(path.join(dir, "users.json"), JSON.stringify(USERS));
  fs.writeFileSync(path.join(dir, "containers.json"), JSON.stringify(CONTAINERS));
}
function writeFlat(dir) {
  for (const t of ["users", "containers"]) fs.mkdirSync(path.join(dir, t), { recursive: true });
  for (const [k, v] of Object.entries(USERS)) fs.writeFileSync(path.join(dir, "users", `${k}.json`), JSON.stringify(v));
  for (const [k, v] of Object.entries(CONTAINERS)) fs.writeFileSync(path.join(dir, "containers", `${k}.json`), JSON.stringify(v));
  // v4 keeps secrets in users/<id>/ subdirs and a .lock dotfile — must be ignored by loadMap
  fs.writeFileSync(path.join(dir, "users", ".lock"), "");
  fs.mkdirSync(path.join(dir, "users", "alice"), { recursive: true });
  fs.writeFileSync(path.join(dir, "users", "alice", "id_ecdsa.pub"), "");
}

function checkMaps(label, users, containers) {
  eq(`${label}: users loaded`, Object.keys(users).sort(), Object.keys(USERS).sort());
  eq(`${label}: containers loaded`, Object.keys(containers).sort(), Object.keys(CONTAINERS).sort());
  const c = classify(users, containers);
  eq(`${label}: real resellers`, c.realResellers.sort(), ["alice"]);
  eq(`${label}: seed 'a' ACTIVE`, c.seedRows.find((r) => r.seed === "a")?.status, "ACTIVE");
  eq(`${label}: seed 'b' vestigial`, c.seedRows.find((r) => r.seed === "b")?.status, "vestigial");
  eq(`${label}: tied users`, c.tiedUsers.map((t) => t.user).sort(), ["bob", "seeduser"]);
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), "wpf-p0-"));
try {
  // (1) v3 monolithic
  const mono = path.join(root, "mono");
  fs.mkdirSync(mono);
  writeMono(mono);
  const um = loadMap(mono, "users");
  eq("v3: loadMap picks users.json", /users\.json$/.test(um.via), true);
  checkMaps("v3-monolithic", um.map, loadMap(mono, "containers").map);

  // (2) v4 flat per-entity — the bug that reported 0 users
  const flat = path.join(root, "flat");
  fs.mkdirSync(flat);
  writeFlat(flat);
  const uf = loadMap(flat, "users");
  eq("v4: loadMap picks users/ dir", /per-entity/.test(uf.via), true);
  checkMaps("v4-flat", uf.map, loadMap(flat, "containers").map);

  // (3) all three reseller-key filename variants under users/<u>/
  const keys = path.join(root, "keys");
  fs.mkdirSync(path.join(keys, "users", "bob"), { recursive: true });
  const variants = ["reseller_id_ecdsa.pub", "reseller_srvctl_id_ecdsa.pub", "srvctl_reseller_id_ecdsa.pub"];
  for (const v of variants) {
    eq(`regex matches ${v}`, RESELLER_KEY_RE.test(v), true);
    fs.writeFileSync(path.join(keys, "users", "bob", v), "");
  }
  fs.writeFileSync(path.join(keys, "users", "bob", "id_ecdsa.pub"), ""); // NOT a reseller key
  const found = scanResellerKeys(keys).map((p) => path.basename(p)).sort();
  eq("scan finds all 3 variants, not id_ecdsa.pub", found, [...variants].sort());
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

console.log(`wpf-phase0-inventory.test: ${pass} passed, ${fails.length} failed`);
for (const f of fails) console.log(`  FAIL ${f.name}: got ${JSON.stringify(f.got)} want ${JSON.stringify(f.want)}`);
process.exit(fails.length ? 1 : 0);
