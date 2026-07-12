// update-campaign/wpf-phase2-remove-vestigial-resellers.test.mjs
// Tests the Phase 2 vestigial-seed removal: the plan (what/blocked), the
// migrated-store guard, and an end-to-end removal through the real store.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createStore } from "../modules/datastore/lib/store.mjs";
import { planRemoval, isMigrated } from "./wpf-phase2-remove-vestigial-resellers.mjs";

let pass = 0;
const fails = [];
const ok = (name, cond) => (cond ? pass++ : fails.push(name));
const eq = (name, got, want) => ok(`${name} (got ${JSON.stringify(got)})`, JSON.stringify(got) === JSON.stringify(want));

// ---- plan: clean host (fx.d250.hu shape) ----------------------------------
{
  const users = { root: { reseller_id: 0 }, alice: {}, bob: {} };
  for (const l of "abcdefghijklmnopqrstuvwx") users[l] = { reseller_id: 1 }; // all vestigial
  const containers = { site: { user: "alice" } };
  const p = planRemoval(users, containers);
  eq("clean: vestigial = all 24 seeds", p.vestigial.length, 24);
  ok("clean: not blocked", p.blocked === false);
}

// ---- plan: blocked hosts ---------------------------------------------------
{
  // an ACTIVE seed (owns a container)
  const users = { root: { reseller_id: 0 }, a: { reseller_id: 1 } };
  const p = planRemoval(users, { c1: { user: "a" } });
  ok("active seed → blocked", p.blocked === true);
  eq("active seed listed", p.activeSeeds, ["a"]);
}
{
  // a REAL reseller (reseller_id, not root, not a seed)
  const users = { root: { reseller_id: 0 }, agency: { reseller_id: 5 }, bob: { reseller: "agency" } };
  const p = planRemoval(users, {});
  ok("real reseller → blocked", p.blocked === true);
  eq("real reseller listed", p.realResellers, ["agency"]);
  eq("tied user listed", p.tiedUsers.map((t) => t.user), ["bob"]);
}

// ---- isMigrated guard ------------------------------------------------------
test_dir((dir) => {
  fs.writeFileSync(path.join(dir, "users.json"), "{}"); // monolithic only
  ok("monolithic-only store → not migrated", isMigrated(dir) === false);
});
test_dir((dir) => {
  fs.mkdirSync(path.join(dir, "users"));
  fs.writeFileSync(path.join(dir, "users", "root.json"), "{}"); // per-entity
  ok("per-entity store → migrated", isMigrated(dir) === true);
});

// ---- end-to-end removal through the real store -----------------------------
test_dir((dir) => {
  const s = createStore(dir, { git: false });
  s.write("users", "root", { reseller_id: 0 });
  s.write("users", "alice", { name: "Alice" });
  for (const l of "abcx") s.write("users", l, { reseller_id: 1 }); // vestigial seeds
  s.write("users", "b", { reseller_id: 2 }); // seed b OWNS a container -> active
  s.write("containers", "site", { user: "b" });
  fs.writeFileSync(path.join(dir, ".per-entity"), "");

  const plan = planRemoval(s.readAll("users"), s.readAll("containers"));
  ok("e2e: b is active, not removable", plan.blocked === true && plan.activeSeeds.includes("b"));
  // (a real run would ABORT here; force the clean case by removing b's container)
  s.remove("containers", "site");
  const plan2 = planRemoval(s.readAll("users"), s.readAll("containers"));
  ok("e2e: now clean", plan2.blocked === false);
  eq("e2e: vestigial seeds a,b,c,x", plan2.vestigial.sort(), ["a", "b", "c", "x"]);

  s.transaction("remove vestigial", (tx) => { for (const l of plan2.vestigial) tx.remove("users", l); });
  eq("e2e: only root+alice remain", s.list("users"), ["alice", "root"]);
  ok("e2e: root untouched", s.has("users", "root") && s.read("users", "root").reseller_id === 0);
});

function test_dir(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wpf-p2-"));
  try { fn(dir); } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}

console.log(`wpf-phase2.test: ${pass} passed, ${fails.length} failed`);
for (const f of fails) console.log(`  FAIL ${f}`);
process.exit(fails.length ? 1 : 0);
