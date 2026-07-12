# 025 — Mixed-version upgrade safety (v3 / half-updated / v4)

Trigger: production hosts got **accidentally half-updated** (code is **rsync'd**,
not git — so a partial rsync leaves a genuinely mixed but per-file-consistent
tree). Requirement: v3, half-updated, and v4 hosts must all **run**, **auto-
upgrade to v4**, and lose **no data**.

The load-bearing risk is the **datastore format transition** (v3 monolithic
`hosts.json`/`users.json`/`containers.json` → v4 file-per-entity
`<type>/<id>.json`). Code-file mismatches from a partial rsync are recovered by
completing the rsync; the datastore layer is what guarantees the DATA survives
and every host converges. Three defenses were added (all in the datastore
engine, fully tested):

## 1. v4 reads fall back to the v3 monolithic files (`store.mjs`)
The public `read`/`readAll`/`has`/`list` now fall back to `<root>/<type>.json`
when a record/type is absent per-entity, MERGING (per-entity wins — it is the
newer, post-migration truth). So a v4 binary on an **un-migrated** store (a host
that got the new code but whose root migration has not run, or the read-only
gluster copy) returns the real data instead of an empty set. The
transaction/write path deliberately does NOT use this fallback (see #2/#3).

## 2. Migration is write-if-absent + transactional (`migrate.mjs`)
`migrateToPerEntity` now writes a record only if the per-entity file is absent
(`tx.has`, which is per-entity-only). So re-running the migration is idempotent,
and a **split store** (some records already written per-entity by v4, the rest
still monolithic — e.g. a crash mid-upgrade) **consolidates safely**: newer
per-entity records survive, monolithic-only records are added, nothing is
clobbered. Still all-or-nothing under one lock (a partial monolithic store fails
hard, unchanged).

## 3. `.per-entity` authoritative marker — keep the monolithic (`datalib.sh`)
`migrate_datastore_to_per_entity` no longer **moves** the monolithic files to
`.monolithic-backup`. It now: consolidates, `cp`-snapshots a backup, and writes
a `.per-entity` marker — **leaving the monolithic originals in place**. Reason:
with alphabetical rsync order (`lib/` → `libs/` → `main.mjs`), a host can get the
new `datalib.sh` **before** the new `main.mjs`; archiving would leave the
still-old reader unable to see its data. Keeping the originals lets old code
keep reading them. To stop v4 deletes from resurrecting via the fallback,
`store.mjs`'s monolithic fallback is DISABLED once `.per-entity` exists (v4 =
per-entity authoritative). `init_datastore`'s trigger skips once the marker is
set, so no churn. A later, fully-v4 cleanup can remove the stale originals.

## What each state does now
| host state | reads | writes / upgrade |
|---|---|---|
| **v3** (v3 code, monolithic) | v3 reads monolithic (unchanged) | runs v3; on rsync to v4 → next root `sc` migrates |
| **half: new datalib, old main** | old main reads monolithic (kept, present) | datalib migrates+marks; old main unaffected; completing rsync → v4 |
| **half: new main, old datalib** | v4 main reads monolithic via **fallback** | no migration yet; completing rsync (new datalib) migrates |
| **v4** (migrated, marker set) | v4 reads per-entity; monolithic ignored | writes/deletes per-entity, correct |

Automatic upgrade of the **data** is the existing `init_datastore` path (every
root `sc` run): idempotent, transactional, now non-clobbering. Automatic upgrade
of the **code** is completing the rsync (below).

## Operational guidance (rsync deployment)
- **Complete the rsync** to every host (idempotent). Recommended: rsync to a
  temp dir then atomically swap `/usr/local/share/srvctl`, so no host runs a
  half-set; failing that, a second full rsync pass converges the tree. Use
  `--delete` so retired v3 files (e.g. `lib.js`) do not linger.
- The **data is never at risk**: the pre-migration monolithic files stay on disk
  (plus a `.monolithic-backup/` snapshot) and per-entity carries the live truth;
  the migration only ever ADDS missing records.
- Once every host is confirmed on v4, a follow-up may delete the now-stale
  monolithic originals (guarded by `.per-entity`). Not required for correctness.

## Caveat (inherent to a partial rsync)
A tree with genuinely interdependent files split across the v3/v4 boundary
(e.g. new `bashlib.sh` calling `node main.mjs` while `main.mjs` is still old, or
a not-yet-copied `store.mjs` import) will error until the rsync completes — this
is a code-completeness problem, not a data problem. The datastore defenses above
guarantee that **whatever** the code state, the DATA is intact and converges to
v4 as soon as consistent code lands.

## Tests
`store.test.mjs` +6 cases (21 total): monolithic fallback; split-store per-entity
wins; consolidating re-migration without clobber; post-migration pure per-entity;
`.per-entity` marker (deletes not resurrected); corrupt monolithic = hard error.
End-to-end verified: v4 `main.mjs get user … name` returns the real value from an
un-migrated v3 monolithic store. Full datastore suite 61/61 + 21/21; broader
guard/harness suites unaffected.
