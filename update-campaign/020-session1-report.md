# 020 — Session 1 report (autonomous overnight, 2026-07-05)

## What was done

Full functionality-preserving polish pass over srvctl v3, on branch `v4`
(from master e179f53). Nothing pushed; the running install at
/usr/local/share/srvctl was never touched; your uncommitted
`add-zerotier.sh` WIP is intact and still uncommitted.

- **Discovery**: 38 read-only agents wrote a fact sheet for core and every
  module (`update-campaign/core.md`, `update-campaign/modules/*.md`) and
  surfaced 301 findings (1 blocker, 34 high, 115 medium, 151 low),
  consolidated in `003-discovery-findings.md`.
- **Polish**: core + all 37 modules rewritten for readability with inline
  documentation, one commit per unit (38 polish commits). Every commit
  keeps identical functionality per the `002-polish-conventions.md`
  contract; only unambiguous broken-path bugs were fixed, everything else
  marked `## FIXME(v4):` in place (428 markers across 174 files).
- **Plan drafts**: `010`–`019` DRAFT architecture docs for the Phase B goals
  (runtime split, module contract, permissions, datastore→boilerplate,
  zerotier, wildcard certs, mail proxy, cockpit, gluster removal,
  coexistence/rollout) — for your review, no code.

## Verification (whole branch)

- All 267 shell files (excluding vendored) parse with `bash -n`.
- All touched JS parses with `node --check`.
- ShellCheck findings tree-wide: **144 → 68** (−53%).

## Bugs actually fixed (broken-path only, safe under 002)

These changed no working behavior — each fixed a path that was already
broken or impossible:

- **BLOCKER** `srvctl/commands/update-install.sh` — `cat completion.sh >
  /etc/bash_completion.d/srvctl-completion` truncated the source file
  through init.sh's symlink on standard installs (`cat X > X` empties X),
  destroying completion and dirtying the install git tree. Now removes the
  destination symlink first; fresh-install path byte-identical.
- core `commonlib.sh` — per-command help lookup missing `.sh` suffix (help
  for every module command was broken); modules.conf cache truncated on
  regeneration instead of growing unbounded.
- core `srvctl.sh` — hard-abort when init.sh fails to load.
- core `lablib.js` — `e.stderr` guard in `get()`.
- usersonhost `add-publickey.sh` — `run ssh-keygen -i > key` wrote run's
  ANSI banner into the converted key so it never verified.
- usersonve `install-qlcplus.sh` — `qlcpuls` path typo left fixtures empty.
- Plus small mechanical fixes (locals leaking as globals, `[ ]`→`[[ ]]`,
  quoting, `cd || return`, dead-assignment removal) and meaning-preserving
  typo fixes in user-visible strings (e.g. "apgain"→"again", "mail que"→
  "mail queue").

## Highest-severity issues found and DEFERRED (marked FIXME(v4), not fixed)

Filed for your review; fixing them changes live behavior or is a product
decision, so they were not touched overnight.

Security:
- codepad publishes each user's plaintext `.password` (also their host login
  password) into the container-readable share tree.
- letsencrypt appends a vendored **expired** DST Root CA X3 to every
  deployed cert bundle and installs it as ca.pem.
- password module derives long-lived DB/user/SSL credentials from `$RANDOM`
  / `Math.random()` (not cryptographic).
- usersonhost sudoers grants **every account** NOPASSWD `srvctl.sh *` (root);
  plaintext password echoed to stdout on change; shell injection via a
  datastore `name` interpolated into a root `adduser`.
- vncproxy: unanchored username → unquoted sqlite INSERT (injection chain).
- ssh: key revocation never propagates (removed users keep container root
  login); sshd_authorization emits one authorized_keys for every user.
- sshpiperd vendored `workingdir.go`: split-before-regexp panic =
  unauthenticated remote DoS.
- datastore: path traversal on the root-owned, internet-reachable
  pki-validation HTTP endpoint.
- The `[[ $SC_UID0 ]]` gate is always true (SC_UID0 is the string
  "true"/"false") in http-redirect, override-in-address, and container
  destroy/remove — deny branches are unreachable.

Correctness / data safety:
- backup `7zlib.sh` bare `exit` reports no-backup as success (status 0).
- backupdb / mariadb wipe the previous dump before the new one is attempted.
- containers `recreate-ve` can restore a stale `tmp_rootfs` over live data;
  all-containers stop/restart use nonexistent machinectl verbs; remote
  backup's quoted `run "ssh … 'mkdir …'"` never evaluates.
- odoo installs a nonexistent `node` package, aborting the whole dnf
  transaction with the error discarded.
- named exit-handler can write a broken `masters {};` zone config.
- wordpress password-restore tool sends `'show tables'` as a literal → 1064,
  dead end-to-end.

Full list with file:line in `003-discovery-findings.md` and the in-tree
`## FIXME(v4):` markers.

## Open decisions waiting on you (seeded in 000-PROMPT / plan drafts)

- Repo/branch strategy for v4 code (currently branch `v4`, not pushed).
- Node runtime distribution + minimum version.
- Mail proxy pick (nginx mail proxy recommended, `017`).
- Cockpit-only vs also boilerplate admin UI in v4.0 (`018`).
- ZeroTier controller hosting + whether to reuse 10.15.x.y (`015`).
- What replaces gluster's shared-storage role — likely nothing (`019`).
- The batch of meaning-preserving typo fixes in output strings (listed per
  module commit) — veto any you rely on verbatim.

## NEXT

Human review of the DRAFT plan set (`010`–`019`) and the disposition matrix
(`000-COVERAGE.md`). No further code until "plans approved" is recorded in
`000-INDEX.md` — except that the polish pass (this session's authorized
scope) is complete.
