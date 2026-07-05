# SRVCTL 4 CAMPAIGN — INDEX (ledger)

Read 000-PROMPT.md first; it is the governing contract.

## Scope amendment (2026-07-05, from the user, overrides the Stage gate for this scope only)

The user pre-approved an overnight **functionality-preserving rewrite/polish
pass** over core and ALL modules ("identical code identical functionality,
just rewritten — all code, all modules up to date, polished, reworked, with
inline documentation"). Explicitly deferred until the user returns: feature
updates, module drops (gluster/openvpn/perdition/gui/resellers), the
bash→mjs architectural migration (G1), and all "advanced new directions".
Those remain gated on human review. Architecture plan docs may be DRAFTED
for morning review, not executed.

## Working setup (facts verified 2026-07-05)

- /srv/srvctl-project is a SYMLINK to /srv/srvctl — one repo, master,
  1 commit ahead of origin, remote git@github.com:LaKing/srvctl.git.
- The RUNNING srvctl is a separate plain copy at /usr/local/share/srvctl
  (/bin/sc → there; not a git repo). Repo edits do not affect the running
  system; nothing reaches other servers unless pushed. DO NOT PUSH without
  the user.
- This host is `v4-devel` (development server, not one of the ~5 prod).
- User WIP left untouched and uncommitted: modules/usersonve/commands/add-zerotier.sh.
- Campaign work happens on branch `v4` (created from master e179f53).
- ShellCheck v0.11.0 available at
  scratchpad node_modules/.bin/shellcheck (npm package; not system-installed).
- Deviation from 000-PROMPT FILING: per-module fact sheets live in
  update-campaign/modules/<name>.md and update-campaign/core.md (37+ files
  would exhaust the 001-099 number space).

## Session log

### Session 1 — 2026-07-05 (autonomous overnight)
- Base commit: e179f53b391b3270d98ae095014e4a425a9746f7 (master, "Checkpoint fabelous"), version 3.2.5.9.
- Plan: ledger + baseline; branch v4; discovery fact sheets (core + 37
  modules); polish core; polish modules in batches with per-module commits;
  draft Phase B plan docs if time permits; morning report.
- Status: IN PROGRESS — see 000-COVERAGE.md for per-module state.

## Document table

| ID | Title | Type | Status |
|----|-------|------|--------|
| 000-PROMPT.md | Governing contract | ledger | active |
| 000-INDEX.md | This ledger | ledger | active |
| 000-COVERAGE.md | Module disposition + polish matrix | ledger | active |
| 001-baseline.md | v3 performance baseline | fact | written |
| core.md, modules/*.md | Fact sheets (discovery) | fact | pending |

## Stage gate record

- Stage 1→2 gate: NOT passed. Only the polish-pass scope amendment above is
  authorized for execution. Everything else awaits "plans approved".

## NEXT

Set at end of session 1. If this session is interrupted: resume from
000-COVERAGE.md state — polish any module still marked [ ], one commit per
module, using the conventions in the session log above.
