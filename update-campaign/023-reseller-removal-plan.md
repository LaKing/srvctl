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

Deliver as a small read-only script (`get`-based) — I can write it next; it must
run per-host because datastores are per-host.

---

## 4. Phased migration (ordering per the execution rule)

Re-tag and `owner_only`-branch removal happen ONLY after the data model migrates.

- **Phase 1 — decouple creation from reseller (data model, back-compat).**
  `newUser` stops requiring `reseller_id` and stops stamping `user.reseller`
  (so an operator/root can create users). Keep READING `reseller`/`reseller_id`
  for now (compat). `container_reseller` keeps its `"root"` fallback. Additive;
  golden/mutator tests updated to the new record shape.
- **Phase 2 — migrate the accounts (per Phase 0).** Any active reseller kept →
  `role=operator`; vestigial a–x seeds → removed from `default-users.json` +
  a one-shot `migrate.mjs` step that strips `reseller`/`reseller_id` from user
  records and removes reseller key symlinks.
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
