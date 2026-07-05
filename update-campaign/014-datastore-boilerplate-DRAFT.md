# 014 — Datastore: v4 storage contract + boilerplate (G2) — DRAFT for review

Status: storage design DECIDED 2026-07-05 (this section is no longer a
draft — it answers "production-grade light JSON storage" while keeping
human-editable JSON). Boilerplate/transport parts remain DRAFT (D12–D14).

## v3 reality (from modules/datastore.md fact sheet)

- Three monolithic JSON files (hosts.json, users.json, containers.json) +
  verb API (get/put/out/cfg/del/new/add) as bash functions that spawn a
  fresh node process per call — ~159 call sites, so hot paths fork node
  constantly (a big chunk of the G1 slowness).
- lib.js is the real brain: derives UID bases, bridges, gateways, IPs,
  nspawn config, /etc/hosts, firewall commands, port maps, postfix relay
  domains from the raw JSON.
- datastore-server.js (port 1030) serves ACME validation files and a
  public containers.json snapshot behind haproxy; rsync syncs data
  between hosts.

## Why v3 was fragile (root causes, from discovery)

1. Non-atomic writes: whole-file `writeFileSync` in place — a crash mid-write
   truncates the store; a partial write corrupts everything.
2. Lost updates: dns-scan.js, opendkim.js, named.js each rewrite the WHOLE
   containers.json from a start-of-process snapshot with no lock; last writer
   wins, silently dropping others' changes. main.js's double-ADD writes
   containers.json twice racing.
3. No concurrency control: a cron `regenerate` and a user command clobber
   each other.
4. No validation: a malformed hand-edit or buggy caller persists garbage.
5. Every module wrote JSON directly — no single enforced path, so the dead
   SC_DATASTORE_RO guard never actually protected anything.

## v4 STORAGE CONTRACT (decided)

Keep plain JSON that a human can read and edit; make the *mechanics*
production-grade. No database, no external dependency (per D4: extract and
own). Four rules:

### 1. One file per entity (directory = table, file = row)
```
$SC_DATASTORE_DIR/
  hosts/<hostname>.json
  users/<username>.json
  containers/<name>.json
  .lock                       # advisory lockfile
  .git/                       # versioned (see rule 4)
```
Kills the lost-update races by construction (writers on different entities
can't collide), makes hand-editing safe (one small document), contains
corruption to a single row, and makes diffs/backups/sync per-entity.

### 2. Atomic writes: temp + fsync + rename
Never write in place. `write <file>.tmp` → `fsync` → `rename()` over target.
Same-filesystem rename is atomic on POSIX: a reader always sees a complete
old or complete new file, never a torn one; a crash can't destroy the live
file. Reads are therefore lock-free (in-process mjs, the G1 win).

### 3. Single writer behind a lock
ALL writes go through one `lib/datastore.mjs`. No module touches a JSON file
directly. That path: acquire advisory lock (lockfile with a stale-timeout —
srvctl is short-lived, so this stays simple) → validate → atomic-write →
git-commit → release. Concurrent invocations serialize instead of clobbering.
The RO-guard lives HERE (fixes the dead SC_DATASTORE_RO). A coarse
store-level lock covers the rare multi-entity transaction (add container +
update the owner's container list) via a `transaction(fn)` helper.

### 4. Validate on write + git-version
- `validate(type, obj)` per entity type: required keys, types, referential
  checks (a container's `user` must exist in users/). Hand-written, no ajv.
  Invalid → refuse, keep the old file, err clearly.
- After each atomic write, `git add <file> && git commit` in
  $SC_DATASTORE_DIR (the module already ships gitlib.sh and v3 already
  git-commits the store). Every change becomes an auditable per-entity diff
  with `git revert` rollback — a better safety net than a DB for hand-managed
  infra.

### Reader/derivation model
- `read(type, id)`, `list(type)` — lock-free parse.
- Derived data (UID base, bridge, gateway, IP, nspawn/network/hosts/firewall
  templates) stays COMPUTED as pure functions over the loaded documents —
  never persisted (removes the drift-bug class; matches boilerplate `fun/`).

### Human-edit affordance (keeps the property you value)
`sc datastore edit <type> <id>` opens `$EDITOR` on that one file UNDER the
lock and VALIDATES on save. Humans still edit JSON by hand — without the
race or the broken-bracket-breaks-everything risk. Raw `$EDITOR` on a file
while the system is quiet still works too (it's just JSON).

### Why not SQLite / lowdb
SQLite is the textbook "production-grade" answer but is binary — it breaks
text-editor inspect/edit, readable diffs, and the git/rsync-sync model, for
transactional safety we get more cheaply at this data volume. lowdb/nedb add
an external dep (against D4) and most still whole-file-rewrite.

## Boilerplate target shape (G2) — still DRAFT (D12–D14)

- A boilerplate 4 module collection `srvctl-modules` with a `datastore`
  module in the d250.hu container's boilerplate instance, as authoritative
  store + admin UI.
- The HOST still needs data at command time (incl. when d250.hu is down/being
  built — the chicken-and-egg case). So: boilerplate instance is SOURCE OF
  TRUTH + UI + sync hub; each host keeps a local **file-per-entity** read
  cache the v4 mjs core reads directly. Bootstrap/disaster paths work from the
  local cache alone.
- File-per-entity makes this tractable: sync and reconcile individual changed
  files (per-entity conflicts), not a monolithic store — see D12.

## Migration (one-time, per server; v4 replaces v3 — D1: no coexistence)

Because v4 replaces v3 in place (same repo, version 4.0.0.0, same entry
point), the on-disk layout changes once:
1. Back up the current datastore dir (git tag + tarball).
2. `datastore-migrate` (one-shot): read the 3 monolithic v3 JSON files →
   write file-per-entity → validate every record → initial git commit.
   Reversible from the backup.
3. v4 core + verb CLI (get/put/...) read/write via lib/datastore.mjs; the
   verb API stays (keeps ~159 call sites working) but now atomic/locked/
   validated. Ported off gradually to typed reads.
4. boilerplate srvctl-modules/datastore stood up later (D12–D14), consuming
   the same file-per-entity layout.

## Boilerplate integration — decisions folded (D12, D13, D14)

- **D12** — srvctl OWNS the JSON files; the boilerplate d250 app READS the
  shared file-per-entity store, and acts on srvctl either by running `sc`
  commands or via a direct srvctl API. Transport for the shared files:
  file-sync (rsync) for v4.0; an authenticated API can come later. srvctl is
  the writer of record for system state; d250 is a consumer/orchestrator on
  top.
- **D13** — build a **fresh `srvctl-modules/datastore`** on boilerplate
  conventions (not a reuse/retrofit of existing d250 models).
- **D14** — ONE boilerplate app instance (d250.hu) as the **governor /
  top-level admin tool** (business-administration layer across all clusters).
  HARD REQUIREMENT: srvctl must be **fully functional with d250.hu down** —
  d250 is a top layer, srvctl is the system-management layer (per-module
  tools) underneath it. So the host file-per-entity store + in-process mjs is
  authoritative for srvctl's own operation; d250.hu governs/reads but srvctl
  never depends on it at runtime.

Layering summary: **srvctl** = system management (owns the datastore, runs on
every host, works standalone). **d250.hu boilerplate app** = business admin
governor (reads the shared store, drives srvctl via CLI/API, cluster-wide).
