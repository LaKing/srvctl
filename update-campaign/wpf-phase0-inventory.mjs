#!/usr/bin/env node
// update-campaign/wpf-phase0-inventory.mjs — WP-F Phase 0 per-host inventory.
//
// READ-ONLY. Reveals the reseller-removal blast radius on ONE production host.
// Run on EACH host (datastores are per-host) BEFORE any migration:
//
//   node update-campaign/wpf-phase0-inventory.mjs [DATASTORE_DIR]
//
// It never writes. It loads the users + containers maps (v3 monolithic
// users.json/containers.json, or v4 per-entity users/<id>.json — store.mjs
// layout <type>/<id>.json), classifies the reseller layer, and prints a
// summary + the records that need a decision.
//
// The a..x seed accounts (default-users.json) are known; a seed is "vestigial"
// if it owns no user and no container, "ACTIVE" otherwise.
//
// Core functions are exported for update-campaign/wpf-phase0-inventory.test.mjs.

import fs from "node:fs";
import path from "node:path";

export const SEED_LETTERS = "abcdefghijklmnopqrstuvwx".split(""); // a..x per default-users.json

// A reseller-key symlink is any file whose name CONTAINS "reseller" and ends
// ".pub" — covers all three variants written across the codebase:
//   reseller_id_ecdsa.pub          (usersonhost/main.js, ssh/libs/userlib.sh)
//   reseller_srvctl_id_ecdsa.pub   (ssh/libs/userlib.sh)
//   srvctl_reseller_id_ecdsa.pub   (usersonhost/main.js:214)
export const RESELLER_KEY_RE = /reseller.*\.pub$/;

// ---- load a type map (monolithic file OR per-entity dir), READ-ONLY ---------
export function loadMap(dir, name) {
  const mono = path.join(dir, `${name}.json`);
  if (fs.existsSync(mono) && fs.statSync(mono).isFile())
    return { via: mono, map: JSON.parse(fs.readFileSync(mono, "utf8")) };
  const perDir = path.join(dir, name);
  if (fs.existsSync(perDir) && fs.statSync(perDir).isDirectory()) {
    const map = {};
    for (const e of fs.readdirSync(perDir)) {
      // v4 store.mjs writes <type>/<id>.json (flat). Skip dotfiles (.lock,
      // .git) and any per-id key SUBDIR (v4 keeps users/<id>/ for secrets).
      if (!e.endsWith(".json") || e.startsWith(".")) continue;
      const f = path.join(perDir, e);
      if (fs.statSync(f).isFile()) map[e.replace(/\.json$/, "")] = JSON.parse(fs.readFileSync(f, "utf8"));
    }
    return { via: `${perDir}/ (per-entity)`, map };
  }
  return null;
}

export function findDatastore(explicit) {
  const candidates = explicit
    ? [explicit]
    : ["/var/srvctl3/datastore", "/etc/srvctl/data", "/etc/srvctl", "/var/local/srvctl/datastore"];
  for (const dir of candidates) if (fs.existsSync(dir) && loadMap(dir, "users")) return dir;
  return null;
}

// ---- classify the reseller layer from the two maps --------------------------
export function classify(users, containers) {
  const ownedUsersOf = {};      // reseller -> [usernames whose .reseller == it]
  const ownedContainersOf = {}; // username -> [container names]
  for (const [name, u] of Object.entries(users)) {
    const r = u && u.reseller;
    if (r && r !== name) (ownedUsersOf[r] ||= []).push(name);
  }
  for (const [cname, c] of Object.entries(containers)) {
    const owner = c && c.user;
    if (owner) (ownedContainersOf[owner] ||= []).push(cname);
  }
  const isReseller = (n) => users[n] && users[n].reseller_id !== undefined;
  const realResellers = Object.keys(users).filter(
    (n) => isReseller(n) && n !== "root" && !SEED_LETTERS.includes(n),
  );
  const seedRows = SEED_LETTERS.filter((l) => users[l]).map((l) => {
    const ou = (ownedUsersOf[l] || []).length;
    const oc = (ownedContainersOf[l] || []).length;
    return { seed: l, ownedUsers: ou, ownedContainers: oc, status: ou + oc > 0 ? "ACTIVE" : "vestigial" };
  });
  const tiedUsers = Object.entries(users)
    .filter(([n, u]) => u && u.reseller && u.reseller !== n && u.reseller !== "root")
    .map(([n, u]) => ({ user: n, reseller: u.reseller, containers: (ownedContainersOf[n] || []).length }));
  return { ownedUsersOf, ownedContainersOf, realResellers, seedRows, tiedUsers };
}

// ---- scan for reseller-key symlinks under <dir>/users/<u>/ ------------------
export function scanResellerKeys(dir) {
  const usersFsDir = path.join(dir, "users");
  const out = [];
  if (!fs.existsSync(usersFsDir) || !fs.statSync(usersFsDir).isDirectory()) return out;
  for (const u of fs.readdirSync(usersFsDir)) {
    const ud = path.join(usersFsDir, u);
    if (!fs.existsSync(ud) || !fs.statSync(ud).isDirectory()) continue; // <id>.json files skipped
    for (const f of fs.readdirSync(ud)) if (RESELLER_KEY_RE.test(f)) out.push(path.join(u, f));
  }
  return out;
}

// ---- CLI --------------------------------------------------------------------
if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = findDatastore(process.argv[2]);
  if (!dir) {
    console.error("Could not locate a datastore with users.json (or users/). Pass the dir:");
    console.error("  node update-campaign/wpf-phase0-inventory.mjs /path/to/datastore");
    process.exit(2);
  }
  const U = loadMap(dir, "users");
  const C = loadMap(dir, "containers") || { via: "(none)", map: {} };
  const { ownedUsersOf, ownedContainersOf, realResellers, seedRows, tiedUsers } = classify(U.map, C.map);
  const symlinks = scanResellerKeys(dir);
  const line = (s = "") => console.log(s);
  line(`WP-F Phase 0 inventory  —  host: ${process.env.HOSTNAME || "(unset)"}`);
  line(`datastore: users <- ${U.via}`);
  line(`           containers <- ${C.via}`);
  line(`totals: ${Object.keys(U.map).length} users, ${Object.keys(C.map).length} containers`);
  line();
  line(`[1] REAL resellers (reseller_id set, not root, not an a..x seed) = ${realResellers.length}`);
  for (const n of realResellers)
    line(`      ${n}  reseller_id=${U.map[n].reseller_id}  owns ${(ownedUsersOf[n] || []).length} users, ${(ownedContainersOf[n] || []).length} containers`);
  line();
  line(`[2] a..x seed accounts present = ${seedRows.length}   (ACTIVE ones block deletion)`);
  for (const r of seedRows) line(`      ${r.seed}  users=${r.ownedUsers} containers=${r.ownedContainers}  -> ${r.status}`);
  line();
  line(`[3] users tied to a non-self, non-root reseller = ${tiedUsers.length}  (lose super-owner on removal)`);
  for (const t of tiedUsers) line(`      ${t.user}  reseller=${t.reseller}  containers=${t.containers}`);
  line();
  line(`[4] reseller_*_ecdsa.pub symlinks on disk = ${symlinks.length}`);
  for (const s of symlinks.slice(0, 50)) line(`      ${s}`);
  if (symlinks.length > 50) line(`      ... (+${symlinks.length - 50} more)`);
  line();
  const activeSeeds = seedRows.filter((r) => r.status === "ACTIVE").length;
  line(`SUMMARY: ${realResellers.length} real resellers, ${activeSeeds} ACTIVE seeds, ${tiedUsers.length} tied users, ${symlinks.length} reseller keys.`);
  line(
    activeSeeds === 0 && realResellers.length === 0 && tiedUsers.length === 0
      ? "  => reseller layer looks VESTIGIAL on this host: removal is low-risk."
      : "  => reseller layer is IN USE on this host: migrate tied users + active resellers (-> role=operator or reassign) before removal.",
  );
}
