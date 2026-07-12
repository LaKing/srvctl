# 024 — Where we stand (continuation prompt)

Read this first to resume the srvctl v4 campaign. It is written to be handed to a
fresh session verbatim. Pair it with `100-work-packages.md` (the running ledger)
and `023-reseller-removal-plan.md` (the active work package).

---

## 1. What this is

srvctl (v3) is a systemd-nspawn container-farm manager for microsite hosting on
Fedora — bash + Node.js (`.mjs`), deployed across many production servers, CLI
invoked as `srvctl` / `sc`. We are executing the **srvctl 4 rewrite** on branch
**`v4`**, in place, as dependency-ordered work packages (WP-A … WP-N) tracked in
`update-campaign/100-work-packages.md`. Foundation (datastore engine + runtime,
WP-A/B/C/D) is done; we are in the **permission/model layer** (WP-E done, WP-F in
progress).

You (the assistant) implement in small provable slices. The user directs at a
high level ("proceed", "go", "open WP-F") and then **rigorously audits each
commit** — frequently finding a real issue and committing their own follow-up
fix, or asking you to. Treat every commit as something that will be adversarially
reviewed; verify before you claim.

## 2. How we work (hard conventions)

- **Branch `v4`, in place.** Never mutate `/usr/local/share/srvctl` (the running
  v3). Build everything, then VM-test, then live.
- **`srvctl.sh` is the USER's uncommitted WIP** (adds `SC_ARGV=("$@")`). It shows
  as the only modified file. **NEVER stage or commit it.** Every commit you make
  must leave `git status --short` showing exactly ` M srvctl.sh` and nothing else
  of yours.
- **Verify before commit.** Keep the CLI working throughout. Run the relevant
  suites (below) and report real output. If something fails, say so.
- **Commits**: subject `v4 WP-x: …`; body explains the *why* + the proof. End
  with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. Commit messages
  often contain backticks / `${...}` — **use `git commit -F <file>`**, never
  `-m` (bash expands it and aborts). See memory `commit-message-shell-expansion`.
- **ShellCheck**: run WITHOUT `-x` for strict claims (`-x` hides cross-file
  SC2034). Touched files must not increase their finding count vs HEAD.
- **Tests must catch the bug**: for every fix, verify the new test FAILS against
  the pre-fix code (revert-and-run), then restore. This is expected, not
  optional.
- **Don't draft speculative unmerged code** ahead of the data/decisions it
  depends on (user's standing call for WP-F) — it just adds drift risk.
- Memory lives at `/var/codepad/.claude/projects/-srv-srvctl/memory/`. Relevant:
  `uid0-is-not-root`, `auth-state-not-from-environment`, `wp-e2-guard-loading-caveat`,
  `commit-message-shell-expansion`.

## 3. Verification suites (the "full green" bar)

```
bash   modules/srvctl/selftest/authgate.test.sh            # 148 passed  (role/owner/service/VE gates; MUST run as non-root)
bash   modules/srvctl/selftest/classification.test.sh      # 38  passed  (every command carries its agreed guard)
node   modules/srvctl/selftest/commandindex.test.mjs       # 282 checks  (parser == bash grep, incl. guard markers)
bash   modules/srvctl/selftest/sandbox/run-harness.sh      # goldens match, live paths untouched
bash   modules/datastore/selftest/run.sh                   # ALL PASSED, incl. verbapi 61/61
node   update-campaign/wpf-phase0-inventory.test.mjs        # 18  passed  (Phase 0 inventory tool)
```
ShellCheck binary used this campaign: the pinned one under the scratchpad
`node_modules/.bin/shellcheck` (host has none). Adjust path per session.

## 4. WP-E — permission model (G11): COMPLETE ✅

The root / operator / user role model plus resource ownership, hardened against a
hostile user who prefixes `sudo`. Design in `012-permission-model-DRAFT.md`;
status details in `100-work-packages.md`. What holds now:

- **`sc_is_root`** (`modules/srvctl/libs/authlib.sh`) = `[[ $SC_USER == root ]] &&
  $SC_UID0` — the ONLY "is root" test for any role decision. Plain uid 0 is NOT
  root: the NOPASSWD sudoers (`srvctl.sh *`) lets any user reach uid 0 with their
  own `SC_USER`. `sudomize` keeps `SC_UID0` (that means "am I escalated yet").
- Guards, all in the always-loaded srvctl authlib: `root_only`, `operators_only`
  (via memoized `sc_role`, which never trusts an inherited `SC_ROLE`),
  `owner_only <type> <id>` (root or the resource owner; owner authorizes on
  OWNERSHIP then `sudomize` + `return 0`; propagates datastore lookup errors),
  and the context markers `hs_only`/`ve_only` (moved here from the containers
  module so they load inside VEs; still always-pass markers — see §6).
- All **38 commands classified** and tagged (`classification.test.sh` manifest).
  Raw-verb dispatch, the generic `sc <service> <op>` shorthand (host services →
  `root_only`), the container service hook (`owner_only`, via a capability token
  `SC_SERVICE_OWNER_AUTHORIZED` — NOT by service name), the openvpn hook
  (`root_only`), and the container machinectl shorthand (`sc poweroff VE` →
  `owner_only`) are all gated. VE side swept: `usersonve` commands are
  `root_only` (VE root = container admin); `add-user` was the one unguarded
  mutator, now fixed.
- **Two documented non-blockers** (not holes): `sc help` role-filtering (blocked
  on the init datastore-selection bootstrap — bare `sc` IS filtered); and making
  `hs_only`/`ve_only` LIVE (they always-pass today; context is enforced by module
  activation + `root_only`; going live is a cross-module change needing VM test).

## 5. WP-F — reseller removal (G6): IN PROGRESS

Plan + full inventory: `023-reseller-removal-plan.md`. Decisions locked (2026-07):
(1) **drop reseller super-ownership entirely** — no role inherits it; (2)
**delete `add-reseller` outright** — operators are granted by root via
`cfg user <u> role operator`, the a–x single-char convention retired; (3) a–x
seeds: delete vestigial, migrate any ACTIVE reseller → `role=operator`.

Model in one breath: `default-users.json` seeds `root` + `a`–`x` (reseller_id
1–24); a user with `reseller_id` IS a reseller; `user.reseller` points to it;
`container.reseller` is DERIVED not stored; `owner_only`'s reseller branch grants
super-ownership; ssh symlinks a reseller's key into each user; `reseller_id` is
NOT in address/uid derivation (clean removal).

| phase | what | status |
|---|---|---|
| 0 | per-host read-only inventory script (`wpf-phase0-inventory.mjs`, tested v3+v4 layouts, 3 key variants) | ✅ built — **awaiting production runs** |
| 1 | `mutators.newUser` no longer requires `reseller_id` / stamps `user.reseller` | ✅ done (96959e8) |
| 2 | migrate accounts from real data (active reseller→operator, delete vestigial, strip fields, remove reseller-key symlinks) | **needs Phase 0 output** |
| 3 | re-tag `reseller_only`→`operators_only` (add-ve-user, usersonhost/add-user, change-user); delete the guard + `${#SC_USER}==1` listing special-cases | needs Phase 2 |
| 4 | drop the `owner_only` reseller branch | needs data migrated |
| 5 | remove the layer (`add-reseller`, `new reseller`/`newReseller`, `derive.container_reseller`, `user_container_list` clause, ssh reseller symlinks, informational `get <container> reseller` displays) | needs 2–4 |

Phase 1 is back-compat for READS (mixed old/new records work) but a real WRITE
change during the deploy window (new users unstamped) — see the rollout caveat in
`023`.

## 5b. Mixed-version upgrade safety (v3 / half-updated / v4) — DONE ✅
Production got accidentally half-updated; code is **rsync'd, not git**. Design +
operational guidance: `025-mixed-version-upgrade-safety.md`. The datastore engine
now guarantees data survives and converges regardless of code state:
`store.mjs` v4 reads fall back to (and merge with) the v3 monolithic
`<type>.json`; `migrate.mjs` is write-if-absent (idempotent, consolidates a split
store, never clobbers); `datalib.sh` keeps the monolithic in place and writes a
`.per-entity` marker that makes v4 treat per-entity as authoritative (so deletes
don't resurrect) — needed because alphabetical rsync order can land new
`datalib.sh` before new `main.mjs`. Data convergence is automatic (root
`init_datastore`) and independent of code convergence. **Boundary (user):** do
NOT add self-healing/self-rsync deployment logic until the real rsync mechanism
is known; temp-dir + atomic swap of `/usr/local/share/srvctl` (with `--delete`)
is the deployment boundary. Tests: store.test 21/21 incl. 6 upgrade-safety cases.

## 6. THE IMMEDIATE NEXT STEP

**Blocked on the user.** Run, on each production host, and share output:
```
node update-campaign/wpf-phase0-inventory.mjs [DATASTORE_DIR]
```
Then, from that real data, generate the concrete **Phase 2 migrator** and land
**Phase 2 → 3 → 4** in order (each verified against the datastore goldens + the
guard probe; re-tag/branch-removal ONLY after accounts migrate, else single-char
resellers get locked out). Do NOT pre-draft Phase 3/4.

## 7. Traps this campaign already hit (don't repeat)

- uid 0 ≠ root (the sudo bypass). Every role decision → `sc_is_root`.
- Never trust inherited auth state from the environment (`SC_ROLE`,
  `SC_SERVICE_OWNER_AUTHORIZED`) — reset before use, resolve unconditionally.
- Don't gate by NAME when you mean "was authorized" — use a capability token set
  after the real check (the `srvctl-nspawn@victim` direct-unit bypass).
- Hooks that call privileged ops (`service_action`, `machinectl`, systemctl)
  DIRECTLY need their own guard — they run before/around the command gate.
- Guard functions must live in an always-loaded lib (srvctl authlib); a guard in
  a module that's inactive in the current context (containers module inside a VE)
  is a silent no-op.
- The `owner_only` escalated-owner path must `return 0` after `sudomize`
  (re-exec is uid 0 but `SC_USER=owner`, so `sc_is_root` is false).

## 8. Commit arc (branch v4, newest first)
```
385978b make v3/half-updated/v4 hosts all run + auto-upgrade, no data loss (025)
d4b336d WP-F: Phase 1 mixed-window rollout caveat (doc)
96959e8 WP-F Phase 1: decouple new_user from the reseller layer
c2a6d49 WP-F Phase 0: fix v4 per-entity read + reseller-key variants; add tests
aa792ac WP-F Phase 0: inventory script + decisions
9f60e0e WP-F: reseller-removal inventory + phased plan (023)
6d543de WP-E VE-side sweep: guard add-user; move ve_only/hs_only to srvctl authlib
cdf4125 WP-E: owner-gate the container machinectl shorthand (proactive sweep)
606d567 WP-E: close direct-unit bypass — capability token, not the name
5467892 WP-E: host-service shorthand=root_only; container re-deny + openvpn bypass
66a9b56 WP-E: owner_only regression + service-shorthand sudo bypass
f3cc559 WP-E: close the sudo bypass — key "root" off SC_USER, not plain uid 0
eeae593 WP-E.2.b audit: guard default container service path
d1fc177 WP-E.2.b-2: classify the remaining commands (all 38)
7269fd0 WP-E.2.b-2 slice 1: operator/owner guards for provisioning + vnc
... (see git log for WP-E.2.a/.b-1 and earlier WP-A/B/C/D)
```

## 9. After WP-F
WP-G (ZeroTier mesh replaces openvpn hostnet), WP-H+ per `100-work-packages.md`.
The reseller super-ownership removal (WP-F) also simplifies future ownership work.
