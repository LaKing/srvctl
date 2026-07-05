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

- /srv/srvctl-project is a SYMLINK to /srv/srvctl — one repo, remote
  git@github.com:LaKing/srvctl.git. The ACTIVE branch is `v4` (created from
  master e179f53); all campaign commits live on v4 and are NOT pushed.
  master is 1 commit ahead of origin from before the campaign.
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
  draft Phase B plan docs; morning report.
- Status: COMPLETE. Branch `v4`, not pushed. 38 polish commits (core + all
  37 modules), one per unit, functionality-preserving per 002.
- Results:
  - Discovery: 301 findings (1 blocker, 34 high, 115 medium, 151 low) in
    003; fact sheets in core.md + modules/*.md; polish-risk register in 004.
  - Polish: 427 `FIXME(v4)` markers across 174 files (reconciled 2026-07-05,
    full list in 021-fixme-inventory.md — supersedes the earlier "428"
    estimate); only broken-path bugs fixed (incl. the completion.sh BLOCKER).
    Verification: all 267 shell files bash -n clean, all touched JS node
    --check clean, ShellCheck 144→68 tree-wide.
  - Plan DRAFTs 010–019 for Phase B (await review).
  - Session report: 020-session1-report.md.
- Uncommitted (left intentionally): modules/usersonve/commands/add-zerotier.sh
  (user WIP).

### Session 1b — 2026-07-05 (reconciliation, after Codex audit-the-audit)
Codex reviewed the campaign against HEAD and filed an addendum in
000-PROMPT.md. All items actioned (docs/ledger only, no source changed):
- Missed consolidations folded into 003 ADDENDUM: srvctl networkd exit-0 on
  failure (networkdlib.sh:125/137/152, HIGH — reached on host update-install
  via containers pre-update-install-host hook); datastore `if $SC_USE_GLUSTER`
  twin of the static finding (MEDIUM, G4-activated).
- 021-fixme-inventory.md generated: complete reconciled list of all 427
  in-tree FIXME(v4) markers (supersedes the "428" estimate). 100-series work
  packages draw from 021, not 003 alone.
- Plan drafts corrected: 010 Hooks section rewritten (v3 has a fixed STARTUP
  sequence + explicit run_hooks groups, NOT a generic pre-$CMD/$CMD/post-$CMD
  command wrapper); 011 gains the SOURCED-SCOPE contract (hooks read/write
  caller locals like rootfs_name; run_hooks drops extra argv — an isolated
  .mjs child dispatcher would break them; per-hook explicit data contracts
  required). Verified against codepad/firewalld/postfix mkrootfs_fedora hooks
  and addcontainerlib.sh:62.
- 019 gains the G4 ORDERING CONSTRAINT: de-gluster datastore+static hooks
  BEFORE dropping the gluster module.
- Ledger drift fixed: 000-COVERAGE postfix polish [x]; 000-INDEX branch note
  (v4, not master); fact-sheet status reconciled to "written" with a
  baseline-grounded (988c38c) caveat.

## Document table

| ID | Title | Type | Status |
|----|-------|------|--------|
| 000-PROMPT.md | Governing contract | ledger | active |
| 000-INDEX.md | This ledger | ledger | active |
| 000-COVERAGE.md | Module disposition + polish matrix | ledger | active |
| 001-baseline.md | v3 performance baseline | fact | written |
| core.md, modules/*.md | Fact sheets (discovery) | fact | written |

CAVEAT (fact sheets): they are BASELINE-GROUNDED — written against commit
988c38c and titled with it, BEFORE the polish commits. Some line numbers and
bug-list entries predate the polish and no longer point at current HEAD.
Treat them as discovery CONTEXT, not HEAD truth; re-verify any file:line
against HEAD before turning it into a Stage-2 work package. The reconciled,
HEAD-accurate marker list is 021-fixme-inventory.md.

## Stage gate record

- Stage 1→2 gate: NOT passed. Only the polish-pass scope amendment above is
  authorized for execution. Everything else awaits "plans approved".

## Document table (session 1 additions)

| ID | Title | Type | Status |
|----|-------|------|--------|
| 002 | Polish conventions | contract | active |
| 003 | Discovery findings (301) | issues | filed |
| 004 | Polish-risk register | fact | written |
| 005 | Polish agent brief | contract | active |
| 010–012 | Runtime / module contract / permissions | plan DRAFT | review |
| 013–019 | Rollout, datastore, zerotier, certs, mail, cockpit, gluster | plan DRAFT | review |
| 020 | Session 1 report | report | written |
| 021 | FIXME(v4) inventory (427, reconciled) | fact | written |
| core.md, modules/*.md | Fact sheets (baseline-grounded, see caveat) | fact | written |

## NEXT

HUMAN REVIEW. Two things need the user:
1. Review the DRAFT plan set (010–019, now corrected per Codex) and the
   disposition matrix (000-COVERAGE.md); record "plans approved" here to
   open Stage 2.
2. Decide the open questions in 020 (repo strategy, mail proxy, cockpit
   scope, zerotier controller, gluster replacement, typo-fix batch).

STAGE-2 PRECONDITIONS carried from the Codex addendum (fold into 100-series
work packages before executing them):
- Draw work packages from 021-fixme-inventory.md (reconciled), not 003 alone.
- Re-verify every fact-sheet file:line against HEAD before use (baseline
  caveat above).
- Preserve the hook contract exactly (010 Hooks + 011 sourced-scope): no
  generic command wrapper; no isolated-child hook dispatch without explicit
  per-hook data contracts.
- Honor the G4 ordering constraint (019): de-gluster datastore+static hooks
  before dropping the gluster module.

The authorized overnight polish scope is COMPLETE — no further source code
until the plan set is approved.
