#!/usr/bin/env node
// update-campaign/wpf-phase2-remove-vestigial-resellers.mjs — WP-F Phase 2.
//
// Removes the VESTIGIAL a..x reseller seed accounts (own no user, no container)
// from a host's datastore. DRY-RUN by default; pass --apply to write.
//
//   node update-campaign/wpf-phase2-remove-vestigial-resellers.mjs [DIR] [--apply]
//
// SAFETY:
//   * Aborts unless the host is CLEAN per Phase 0 — 0 real resellers, 0 tied
//     users, 0 ACTIVE seeds. A host with active reseller usage needs the
//     operator-migration path first (migrate resellers -> role=operator), NOT
//     blind deletion, so this refuses to touch it.
//   * Re-verifies each seed is vestigial at apply time (not just from Phase 0).
//   * Only ever removes single-letter a..x seed user records — never root, never
//     a real user.
//   * Idempotent: re-running after --apply removes nothing.
//   * Requires a MIGRATED (v4 per-entity) store; refuses a monolithic-only one
//     (run any root `sc` first to migrate). Deletions go through the store
//     (per-entity + git commit); the .per-entity marker makes v4 ignore any
//     stale monolithic copy of the seed.

import fs from "node:fs";
import path from "node:path";
import { createStore } from "../modules/datastore/lib/store.mjs";
import { classify, SEED_LETTERS } from "./wpf-phase0-inventory.mjs";

// Pure plan: what would change + why it might be blocked. Exported for tests.
export function planRemoval(users, containers) {
  const { realResellers, seedRows, tiedUsers } = classify(users, containers);
  const vestigial = seedRows.filter((r) => r.status === "vestigial").map((r) => r.seed);
  const activeSeeds = seedRows.filter((r) => r.status === "ACTIVE").map((r) => r.seed);
  const blocked = realResellers.length > 0 || tiedUsers.length > 0 || activeSeeds.length > 0;
  return { realResellers, tiedUsers, activeSeeds, vestigial, blocked };
}

// True only when the store is already v4 per-entity (has the marker, or real
// per-entity user files). A monolithic-only store must be migrated first.
export function isMigrated(dir) {
  if (fs.existsSync(path.join(dir, ".per-entity"))) return true;
  const udir = path.join(dir, "users");
  try {
    return fs.readdirSync(udir).some((n) => n.endsWith(".json") && !n.startsWith("."));
  } catch {
    return false;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const apply = args.includes("--apply");
  const dir = args.find((a) => !a.startsWith("--")) || "/var/srvctl3/datastore";
  const die = (msg) => { console.error(msg); process.exit(1); };

  if (!fs.existsSync(dir)) die(`datastore dir not found: ${dir}`);
  if (!isMigrated(dir))
    die(`datastore at ${dir} is not migrated to v4 per-entity yet.\nRun any root \`sc\` command first to migrate, then re-run this.`);

  const store = createStore(dir, { git: true });
  const users = store.readAll("users");
  const containers = store.readAll("containers");
  const plan = planRemoval(users, containers);

  console.log(`host: ${process.env.HOSTNAME || "(unset)"}   datastore: ${dir}`);
  if (plan.blocked) {
    console.error("NOT CLEAN — this host still has active reseller usage:");
    if (plan.realResellers.length) console.error(`  real resellers: ${plan.realResellers.join(" ")}`);
    if (plan.activeSeeds.length) console.error(`  ACTIVE seeds:   ${plan.activeSeeds.join(" ")}`);
    if (plan.tiedUsers.length) console.error(`  tied users:     ${plan.tiedUsers.map((t) => `${t.user}->${t.reseller}`).join(" ")}`);
    die("Aborting: migrate active resellers to role=operator (or reassign) before removing seeds.");
  }

  if (plan.vestigial.length === 0) {
    console.log("Nothing to do: no vestigial a..x seed accounts present.");
    process.exit(0);
  }
  if (!apply) {
    console.log(`DRY-RUN: would remove ${plan.vestigial.length} vestigial a..x seed users:`);
    console.log(`  ${plan.vestigial.join(" ")}`);
    console.log("Re-run with --apply to remove them (committed to the datastore git).");
    process.exit(0);
  }

  // Re-verify vestigial inside the lock, then remove in ONE transaction/commit.
  const removed = [];
  store.transaction("WP-F Phase 2: remove vestigial a..x reseller seed accounts", (tx) => {
    for (const letter of plan.vestigial) {
      if (!SEED_LETTERS.includes(letter)) continue; // belt: never non-seed
      const owedUsers = Object.values(tx.readAll("users")).some((u) => u && u.reseller === letter);
      const owedCtrs = Object.values(tx.readAll("containers")).some((c) => c && c.user === letter);
      if (owedUsers || owedCtrs) continue; // became active — skip defensively
      if (tx.remove("users", letter)) removed.push(letter);
    }
  });
  console.log(`Removed ${removed.length} vestigial a..x seed users: ${removed.join(" ")}`);
}
