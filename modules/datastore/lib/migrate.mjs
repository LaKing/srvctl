// modules/datastore/lib/migrate.mjs — one-shot v3→v4 datastore conversion.
//
// v3 stored three MONOLITHIC files, each a { id: record } map:
//   hosts.json, users.json, containers.json
// v4 stores FILE-PER-ENTITY under <root>/<type>/<id>.json (see store.mjs).
//
// This module converts monolithic → per-entity, and exports per-entity →
// monolithic, so a round-trip proves the migration is lossless (selftest).
// resellers are DERIVED from users in v3 (any user with reseller_id) — they
// were never a stored file, so they are not migrated.

import fs from "node:fs";
import path from "node:path";
import { createStore, StoreError } from "./store.mjs";

// The three v3 monolithic files, mapped to their v4 entity type (directory).
export const MONOLITHIC = [
  { type: "hosts", file: "hosts.json", required: true },
  { type: "users", file: "users.json", required: false },
  { type: "containers", file: "containers.json", required: false },
];

function loadMonolithic(srcDir, { file, required }) {
  const p = path.join(srcDir, file);
  let raw;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (err) {
    if (err.code === "ENOENT") {
      if (required) throw new StoreError("MIGRATE-MISSING", `required ${p} not found`);
      return {}; // optional file absent → empty set
    }
    throw err;
  }
  let obj;
  try {
    obj = JSON.parse(raw);
  } catch (err) {
    throw new StoreError("MIGRATE-PARSE", `corrupt ${p}: ${err.message}`);
  }
  if (obj === null || typeof obj !== "object" || Array.isArray(obj)) {
    throw new StoreError("MIGRATE-SHAPE", `${p} is not a {id: record} map`);
  }
  return obj;
}

// Migrate srcDir's monolithic files into the store. All entities are written
// under ONE lock and ONE git commit (fast + atomic-ish for a one-shot).
// Returns per-type counts.
export function migrateToPerEntity(srcDir, store) {
  const counts = {};
  store.transaction("migrate: v3 monolithic → v4 file-per-entity", (tx) => {
    for (const spec of MONOLITHIC) {
      const map = loadMonolithic(srcDir, spec);
      let n = 0;
      for (const id of Object.keys(map)) {
        tx.write(spec.type, id, map[id]);
        n++;
      }
      counts[spec.type] = n;
    }
  });
  return counts;
}

// Read the per-entity store back into v3-style monolithic { id: record } maps.
// Used to verify round-trip identity against the original files.
export function exportToMonolithic(store) {
  const out = {};
  for (const spec of MONOLITHIC) out[spec.type] = store.readAll(spec.type);
  return out;
}

// CLI:  node migrate.mjs <srcDir-with-monolithic-json> <dstDir-store>
if (import.meta.url === `file://${process.argv[1]}`) {
  const [srcDir, dstDir] = process.argv.slice(2);
  if (!srcDir || !dstDir) {
    console.error("usage: node migrate.mjs <srcDir> <dstDir>");
    process.exit(2);
  }
  // git:false — the bash datastore layer (libs/gitlib.sh datastore_push)
  // owns the git commit, so the migration must not double-commit.
  const store = createStore(dstDir, { git: false });
  const counts = migrateToPerEntity(srcDir, store);
  console.log("migrated:", JSON.stringify(counts));
}
