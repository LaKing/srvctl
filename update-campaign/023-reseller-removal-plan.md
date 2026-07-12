# 023 — WP-F reseller removal: inventory + migration plan

Status: **INVENTORY COMPLETE, no code/data changed.** Per the execution rule
"inventory + migration plan before deleting anything." Deletion/re-tag happens
only after the data model is migrated and the open decisions below are made.

Goal (G6): remove the reseller layer — `reseller_only`, the pre-seeded a–x
accounts, `reseller_id`, `container.reseller`, and the `owner_only` reseller
branch — after the role model (WP-E: root / operator / user) has replaced it.

---

## 1. Inventory — every reseller touch point

### 1a. Data model (datastore engine)
- **`modules/datastore/default-users.json`** — seed table: `root`
  (`reseller_id: 0`) plus **`a`–`x`** (24 accounts, `reseller_id` 1–24, `uid`
  1001–1024, NATO phonetic `name`). Seeded by `libs/datalib.sh:96`. NOTE: a–x
  only — no `y`/`z`.
- **User record fields**: `reseller_id` (present ⇒ this user *is* a reseller)
  and `reseller` (points to the user's reseller; for a reseller, itself).
- **`mutators.newUser`** (`lib/mutators.mjs:88`): **throws `MISSING
  RESELLER_ID`** unless `users[SC_USER].reseller_id` is defined, then sets
  `user.reseller = SC_USER`. ⇒ *only a reseller can create a user*, and every
  user is stamped with its creating reseller.
- **`mutators.newReseller`** (`:101`): allocates next `reseller_id`, sets
  `user.reseller = self`.
- **`derive.container_reseller`** (`lib/derive.mjs:120`, exported as `reseller`):
  container.reseller is **DERIVED, not stored** — the owning user's reseller
  (or the user itself if it is a reseller, else `"root"`).
- **`migrate.mjs:9`**: notes resellers are derived from users (any `reseller_id`).

### 1b. Auth / guards
- **`reseller_only`** guard (`modules/srvctl/libs/authlib.sh:77`):
  `[[ ${#SC_USER} == 1 ]] || sc_is_root` — single-char username (a–x) or root.
  Callers (3, the transitional set): `containers/commands/add-ve-user.sh`,
  `usersonhost/commands/add-user.sh`, `usersonhost/commands/change-user.sh`.
- **`owner_only` reseller branch** (`authlib.sh:118,125`): `get <type> <id>
  reseller` + `|| SC_USER == $_reseller` ⇒ **a reseller has super-ownership of
  all its users' containers.** This is the key semantic the role model drops.
- **Listing filters** (`commonlib.sh:273,300`): `${#SC_USER}==1` special-cases a
  single-char caller as a reseller (shows reseller_only commands).

### 1c. Listing / generators
- **`generators.user_container_list`** (`:355`) and the cluster list (`:358`):
  a reseller sees containers whose owning user's `reseller === SC_USER`.

### 1d. Provisioning + display (bash)
- **`add-reseller`** command → `new reseller` verb + `regenerate_users`.
- **`get <container> reseller`** displayed (informational) in: `http-redirect`,
  `https-redirect`, `override-in-address`, `backup-ve`, `remove-ve`,
  `destroy-ve`, `recreate-ve`, `containers/libs/statuslib.sh`.
- **`get user <u> reseller`** read in: `add-ve-user`, `add-user`, `change-user`
  (`change-user` is already a STUB).

### 1e. SSH coupling (blast radius)
- **`modules/ssh/libs/userlib.sh:72`**: for a user whose `reseller` is not self
  and not root, symlinks `users/<u>/reseller_id_ecdsa.pub` →
  `../<reseller>/id_ecdsa.pub` (and `reseller_srvctl_id_ecdsa.pub`). ⇒ the
  reseller's ssh key is placed for the user — reseller ssh access into the
  user's world. Whatever authorizes `reseller_*_ecdsa.pub` must be found in
  Phase 0.

### 1f. NOT coupled (good news)
- `reseller_id` is **NOT used in address/uid/bridge/gateway derivation** — only
  in `container_reseller` detection. So removal needs **no re-addressing**.

---

## 2. Key semantic change (needs a decision)

The reseller layer grants **super-ownership**: a reseller can act on and ssh
into all of its users' containers (`owner_only` reseller branch + ssh symlinks +
`user_container_list`). The WP-E role model deliberately says **operators do NOT
bypass ownership**. So removing reseller = **that super-ownership disappears; no
role inherits it.** After migration, a user's containers are managed by the user
(and root); an ex-reseller does not cross-manage its former users unless it is
root.

**DECISION 1 — is dropping reseller super-ownership acceptable?** (Recommended:
yes — it is the whole point of G6 and matches the role model. If some grouping
must survive, that is a new feature, not part of removal.)

**DECISION 2 — what happens to the a–x seed accounts + any real resellers?**
Options: (a) delete unused ones, migrate any active one to `role=operator`;
(b) keep as ordinary users. This depends entirely on the Phase 0 per-server
inventory (production data I cannot see from here).

---

## 3. Phase 0 — per-server inventory (run on EACH production host FIRST)

Cannot proceed to any change until we know the blast radius. Queries against the
live datastore (`/var/srvctl3/datastore` or per-entity `users/`, `containers/`):

1. Resellers in use: users with `reseller_id` defined **other than root and the
   untouched a–x seeds** (i.e. real `add-reseller` accounts).
2. For each a–x seed: does it own any user (`user.reseller == <letter>`) or any
   container (`container.user == <letter>`)? ⇒ active vs vestigial.
3. Users whose `reseller` is a non-root, non-self value ⇒ who relies on the
   reseller relationship.
4. Presence of `users/*/reseller_*_ecdsa.pub` symlinks and any
   `authorized_keys` / sshpiperd config that references them.
5. Any containers whose only management path today is the reseller branch (owner
   differs from the human who operates it).

**Script: `update-campaign/wpf-phase0-inventory.mjs`** (READ-ONLY, no deps).
Run per-host (datastores are per-host):

```
node update-campaign/wpf-phase0-inventory.mjs [DATASTORE_DIR]
```

Auto-detects `/var/srvctl3/datastore` etc.; reads v3 monolithic
`users.json`/`containers.json` or v4 per-entity. Reports: [1] real resellers,
[2] a–x seed ACTIVE/vestigial, [3] users tied to a non-self reseller, [4]
`reseller_*_ecdsa.pub` symlinks (all three name variants:
`reseller_id_ecdsa.pub`, `reseller_srvctl_id_ecdsa.pub`,
`srvctl_reseller_id_ecdsa.pub`), and a verdict (vestigial ⇒ low-risk removal;
in-use ⇒ migrate tied users + active resellers first). Tested by
`wpf-phase0-inventory.test.mjs` (18 checks: v3 monolithic, v4 flat per-entity,
and all three key-filename variants). Collect its output from every production
host before Phase 2.

### Decisions made (2026-07-08)
1. **Drop reseller super-ownership entirely** — confirmed. No role inherits it.
2. **Delete `add-reseller` outright** — operators are granted by root via
   `cfg user <u> role operator` (no new command); the a–x single-char
   convention is retired.
3. a–x accounts: delete vestigial, migrate any ACTIVE reseller to
   `role=operator` — pending each host's Phase 0 output.

---

## 4. Phased migration (ordering per the execution rule)

Re-tag and `owner_only`-branch removal happen ONLY after the data model migrates.

- **Phase 1 — decouple creation from reseller (data model). ✅ DONE.**
  `mutators.newUser` no longer throws `MISSING RESELLER_ID` and no longer
  stamps `user.reseller` — any authorized caller can create a user, and new
  users carry no reseller (`container_reseller` derives `"root"`). Still READS
  `reseller`/`reseller_id` for existing records (compat). The single v3
  divergence is isolated: `new_user` moved from the v3 oracle to explicit v4
  assertions in `mutators.test.mjs` (incl. a non-reseller actor may now create),
  the `new-user` case in `golden.json` dropped carol's `reseller`, and both are
  documented in-place. `new reseller` untouched (later phase). Full datastore
  suite 61/61 + mutators 9/9; command guards (add-user still `reseller_only`)
  unchanged — the re-tag is Phase 3.
  - **ROLLOUT CAVEAT (mixed window):** this is back-compat for *reads*, but it
    is a real *write* behavior change — while this branch is deployed and active
    resellers are still creating users, those new users are NOT stamped under a
    reseller (no `user.reseller`). That matches the WP-F direction but is not
    invisible: it changes who "owns" users created during the window. Options at
    deploy time: (a) accept it (the reseller relationship is going away anyway),
    or (b) briefly pause reseller-driven user creation until Phases 2–4 land.
    Decide per host from the Phase 0 output (a host with 0 active resellers has
    no window to worry about).
- **Phase 2 — remove the vestigial seeds. ✅ MIGRATOR BUILT + TESTED (user
  runs it on prod).** Phase 0 on `fx.d250.hu` (already v4 per-entity; 58 users,
  50 containers): **0 real resellers, all 24 a–x seeds vestigial, 0 tied users,
  0 reseller keys** → the reseller layer is entirely dead. So Phase 2 is a pure
  deletion — no operator migration needed. Deliverables:
  `wpf-phase2-remove-vestigial-resellers.mjs` (DRY-RUN default, `--apply` to
  write; aborts unless the host is CLEAN — 0 real resellers / 0 tied users / 0
  ACTIVE seeds; re-verifies vestigial under the lock; only ever removes a–x
  seed records; idempotent; requires a migrated store; removes via one
  store.transaction/git-commit). `default-users.json` trimmed to seed only
  `root` (fresh installs). Tests: `.test.mjs` 14/14; CLI verified dry-run →
  apply(24 removed) → idempotent no-op; store suite 21/21 still green.
  Per-host: run the migrator (dry-run first) on EACH host — it self-aborts on
  any host that is not clean. Field-stripping (`reseller`/`reseller_id` on the
  remaining records) is deferred to Phase 5 with the derivation removal.
- **Phase 3 — re-tag guards (only now safe).** `reseller_only` →
  `operators_only` on `add-ve-user`, `add-user`, `change-user`. Delete the
  `reseller_only` function and the `${#SC_USER}==1` special-cases in
  `commonlib.sh` listing + update `classification.test.sh`. (Doing this BEFORE
  Phase 2 would lock out any still-single-char reseller, since they are not
  `role=operator`.)
- **Phase 4 — remove the owner_only reseller branch.** Drop `get <>
  reseller` + the reseller clause; `owner_only` becomes owner-or-root only.
- **Phase 5 — remove the layer.** Delete `add-reseller` + `new reseller` verb +
  `newReseller`, `derive.container_reseller`, the `user_container_list` reseller
  clause, the ssh reseller-key symlinks, and the informational
  `get <container> reseller` displays (or make them degrade cleanly).

Each phase: verify (authgate / classification / commandindex / datastore golden
/ harness) before commit; keep the CLI working throughout; VM-test before live.

---

## 5. Open decisions for the user
1. Drop reseller super-ownership entirely (recommended) — confirm.
2. a–x seed accounts: delete-if-vestigial + migrate-active-to-operator — confirm
   the policy (final answer needs Phase 0 data).
3. Should `add-reseller` be deleted outright, or repurposed as `add-operator`
   (set `role=operator`)? (Recommended: replace with an explicit operator-grant
   command rather than the single-char convention.)
