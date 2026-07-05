# 010 — v4 runtime architecture (G1: light bash + .mjs core) — DRAFT for review

Status: DRAFT written session 1 (autonomous). Not approved. No code follows
from this document yet.

## What makes v3 slow (observed in core, commit 988c38c)

- Every invocation re-walks all 37 module dirs several times in pure bash:
  test_srvctl_modules, load_libs, run_hook × (pre-init, init, post-init,
  pre/post-$CMD), hint_on_file greps every command file for help/permission
  markers (3-4 `head|grep` subprocesses per file — ~80+ command files means
  hundreds of forks just for `sc help`).
- All /etc/srvctl/*.conf sourced every run; module conditions cached in
  modules.conf but everything else recomputed.
- Heavy commands shell out per-container (to be measured per module in
  Phase A; baseline: 001-baseline.md).

## Proposed v4 shape

Bash remains the front door and the stable command/hook boundary. Node is an
implementation engine invoked by bash only when a command's logic benefits
from it.

```
/bin/sc -> srvctl.sh (bash: env guard, role gate, startup hooks, dispatch)
              |
              v
          bash runtime
              - loads/caches /etc/srvctl config and the command index
              - resolves CMD -> modules/<name>/commands/<cmd>.sh
              - sources bash hooks/commands in caller scope
              - calls node core/srvctl.mjs <task> only for ported heavy logic
                (datastore parsing/writes, templating, indexing, derivation)
```

- `runtime.sh` = merged, trimmed lablib.sh + commonlib.sh: output helpers,
  exif/eyif, run, hint, role/ownership guards, hook dispatch, command index
  helpers — only what command/hook scripts actually use.
- Hooks — CORRECTED CONTRACT (per Codex audit; earlier draft was wrong):
  v3 does NOT wrap every command in pre-$CMD/$CMD/post-$CMD. The actual v3
  contract is two distinct things and v4 must preserve BOTH exactly:
    1. STARTUP sequence, fixed, from init.sh:181-204 (HEAD; verify per
       package — line refs are baseline-fragile), run on every invocation in
       this order: `run_hook pre-init-$CMD`, `run_hook pre-init`, (help
       breakout), `load_libs`, `run_hook init`, `run_hook post-init`,
       `run_hook post-init-$CMD`.
    2. EXPLICIT hook groups: `run_hooks X` (= pre-X, X, post-X) fired only at
       specific call sites (commonlib.sh:111-116) — e.g. update-install-host,
       update-install-ve, regenerate, diagnose, adjust-service, add-ve. There
       is NO implicit wrapper around arbitrary command dispatch.
  Each `run_hook` iterates enabled modules in SC_MODULES order and SOURCES
  hooks/<name>.sh into the CURRENT shell (see the sourced-scope contract in
  011). v4 may cache a hook index for speed, but must keep: the exact startup
  order above, the explicit-only nature of run_hooks (no generic command
  wrapper), module iteration order, and the sourced-scope semantics.
  Do NOT implement a generic per-command hook wrapper unless a plan
  intentionally changes this contract AND audits every existing hook user.
- Help/hints: generated from the cached command index (no grep storm);
  `## @en` metadata parsed once at index build.
- Target: `sc help` < 50 ms; dispatch overhead of any command < 30 ms;
  identical CLI surface.

## Compatibility rules (during the whole v4 line)

- Module tree layout unchanged (G12; see 011-module-contract-DRAFT.md).
- Every command/hook keeps a bash entry file. A ported command may delegate
  heavy logic to .mjs, but the callable CLI/hook surface remains .sh unless
  a later, explicit permission/security plan changes that.
- /etc/srvctl/*.conf remain valid inputs; any JSON/cache mirror is generated
  for speed so node does not need to parse bash conf repeatedly.
- Root/user custom includes (/root/srvctl-includes, ~/srvctl-includes)
  keep working through the bash boundary.

## Decisions folded (D1, D2, D3, D5)

- **D1** — v4 continues in the SAME repo (/srv/srvctl-project), version
  **4.0.0.0**, the SAME entry point (`/bin/sc`). No side-by-side install, no
  v3/v4 coexistence — in-place step-by-step upgrade (see 013).
- **D5 + D2** — the ENTRY POINT for everything stays **bash**: `sc` is a
  bash script that dispatches, and invokes node only when a command's logic
  needs it. So the shape is bash-shim → (node when needed), not node-first.
  On startup the shim CHECKS Node ≥ 20 and exits with a clear error if it's
  missing/older (D2). Distro nodejs; no bundled runtime.
- **D3** — when a command delegates to node, the node side runs
  **in-process** in that one node invocation (the G1 fast path; srvctl is
  short-lived), WITH progress indication for anything slow so the user sees
  work happening. No fresh child per internal helper/task.
- **D4 (see 011)** — minimize dependencies; own the code. The "merged
  trimmed runtime.mjs" above is built from srvctl's own extracted helpers,
  not a framework import.

Consequence for the shape above: the process model is `sc` (bash) → source
the selected command/hook in bash caller scope; if that command has ported
heavy logic, it makes one `node core/srvctl.mjs <task>` call that does the
node work in-process and streams progress. The 50ms/30ms targets stand, but
the boundary is bash-first, not node-first.
