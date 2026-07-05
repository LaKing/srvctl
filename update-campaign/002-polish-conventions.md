# 002 — Polish conventions (the overnight identical-functionality pass)

Contract for every polish change on branch v4, session 1. Embedded in each
polish agent's instructions; also the review checklist for commits.

## Prime rule

Identical functionality. A user running any srvctl command before and after
the polish must see the same behavior, same output text, same exit codes,
same files written, same services touched. When in doubt, change less.

## MUST PRESERVE exactly

- Command names, argument meanings, dispatch behavior.
- The `## @@@`, `## @en`, `## &en`, `## &&&` help metadata lines (improving
  grammar/typos in these is allowed ONLY when the meaning is unchanged —
  they are user-visible help, not logic).
- User-visible output strings of msg/ntc/prg/err/log calls (typo fixes
  allowed, wording changes not).
- Exit codes, `return` codes (the numeric ones are conventions: 10 = not
  under srvctl, 54, 132-135, 250...).
- Paths read/written, config file formats, systemd unit contents, datastore
  keys, environment/exported variable names, SC_* names.
- Hook execution order and side-effect order within scripts.
- The guard line `[[ $SRVCTL ]] || exit 10` at the top of sourced scripts.

## ALLOWED (this is the polish)

- Inline documentation: a header comment block per script (what it does,
  when it runs, what it touches), short comments on non-obvious logic.
  Keep the existing `##` comment style of the codebase.
- `local` declarations, consistent `[[ ]]` over `[ ]`, `$(...)` over
  backticks, consistent 4-space indent, then/do placement per existing
  Google-shell-style-with-newlines convention (see srvctl.sh header).
- Quoting fixes ONLY where provably behavior-identical for all plausible
  inputs (e.g. `[[ $x == y ]]` → quoting not needed; `cd $dir` → `cd "$dir"`
  is a real behavior change if $dir could contain spaces — see BUGS below).
- Removing clearly abandoned commented-out code blocks (note each removal
  in the change summary). Keep short informative comments.
- ShellCheck compliance: fix what is safe; `# shellcheck disable=SCXXXX`
  with a one-word reason where the code is intentional.

## BUGS found while polishing

- Unambiguous mechanical defect AND the fix cannot change any currently-
  working behavior (only broken/impossible paths): fix it, list it in the
  change summary under "bugs fixed".
- Anything else (behavior-changing fix, judgment call, security concern):
  do NOT fix. Mark the line with `## FIXME(v4): <one-line defect>` and list
  it under "bugs found, not fixed". These become campaign issues.

## FORBIDDEN tonight

- New features, new flags, new dependencies, performance rewrites.
- Renaming functions or variables used across files.
- The bash→mjs migration (gated on user review of the architecture plans).
- Touching: vendored code (modules/vncproxy/waf/, modules/vncproxy/vncproxy/,
  any demos/, any node_modules), modules/usersonve/commands/add-zerotier.sh
  (user WIP), .git, var/, live-conf/.
- git commands that change state (the orchestrator commits, one commit per
  module).
- Running srvctl or any command that changes system state. Verification is
  static only (bash -n, shellcheck).

## Verification per file/module

1. `bash -n` on every changed .sh — must pass.
2. shellcheck (v0.11.0, scratchpad node_modules/.bin/shellcheck) — issue
   count must not increase; report before/after counts.
3. `node --check` on changed .js/.mjs (if any get comment-only touches).
4. Reviewer (orchestrator) reads the full diff before committing.

## Change summary format (returned by each polish agent)

- files touched, lines +/-
- shellcheck before → after counts
- bugs fixed (file:line, one sentence each)
- bugs found not fixed / FIXME(v4) added (file:line, severity, sentence)
- commented-out dead code removed (file:line ranges)
- anything skipped and why
