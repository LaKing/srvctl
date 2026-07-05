# 012 — v4 permission model (G11) — decisions folded (D9, D10, D11)

Status: direction DECIDED 2026-07-05 (D9/D10/D11). Mechanics below are the
plan; refine into a work package. NOT yet a work package.

## v3 reality (commit 988c38c)

Enforcement is per-script convention, and admittedly unfinished:
- `root_only` (authlib.sh:3) — exits 44 unless UID 0; also leaks a stray
  `echo "SC_UID0 true"` into every root command's output.
- `reseller_only` (authlib.sh:14) — "reseller" = any ONE-CHARACTER username
  (the a..z pre-created accounts; removed under G6).
- `authorize` (authlib.sh:32) — a stub: prints "DEV (Authorization
  implementation not complete.)" and returns success for non-root.
- `sudomize` (authlib.sh:46) — re-execs via sudo, passes all args as one
  collapsed string ($SC_COMMAND_ARGUMENTS = "$*"); `exit $?` after debug
  masks failures.
- Help visibility ≠ permission: hint_on_file hides hints by marker but
  execution is gated separately (or not at all).

## v4 DECISIONS

### Roles (D9)
Three roles, replacing the reseller layer (G6):
- **root** — host admin, allowed everything for everyone.
- **operator** — co-workers employed by root: their OWN usernames, limited
  capacity (a subset of root's commands). NEW role.
- **user** — owns their own containers/resources; acts on what they own.

### sc runs everywhere, for everyone (D10)
- `sc` is the primary CLI — more important than any GUI/cockpit. Root,
  operators, and users must all be able to run `sc` **anywhere**: on the
  host AND inside containers.
- Plain `sc` (no args) displays exactly the commands available to the
  caller's role — role-filtered visibility, computed from the same policy
  that gates execution (no more "hint hidden but command still runs", and no
  "command documented but forbidden").
- This overrides the earlier draft's "users only via cockpit" idea. Cockpit
  (G5) is postponed (D24/D25); `sc` is the interface.

### Enforcement (guards, kept simple per D10)
- Keep **`root_only`** (fix the stray `echo` leak; keep exit 44).
- Add **`operators_only`** — a guard that passes for root+operator, else
  denies (a "checks for violations" routine, symmetric with root_only).
- **Ownership** for `user`: resource-bound commands check the caller owns
  the target (container/site) against the datastore (D11) — a
  `owner_only <resource>` guard.
- One place decides: the dispatcher resolves the caller's role once and the
  guards read it; the always-true `[[ $SC_UID0 ]]` string-gate bugs found in
  discovery (http-redirect, destroy-ve, remove-ve, map-port) are fixed by
  using the resolved role, not a string test.
- `authorize` stub is replaced by these concrete guards. `sudomize` survives
  as a dispatcher feature (auto-sudo for root/operator commands) with argv
  passed as an array (fixes the collapse bug).
- Audit: privileged commands logged (keep srvctl-root.log); denials logged
  with the failing guard.

### Where roles/ownership live (D11)
- The datastore is the source of truth (see 014-datastore storage contract):
  `users/<name>.json` carries the role; `containers/<name>.json` carries the
  owner. v4 enforces from the datastore; no username-shape heuristics.
- Operators are provisioned as real Unix users with `role: operator` in
  their datastore user record.

## Migration notes
- The a..z reseller accounts are removed as a Stage-2 step with a per-server
  user inventory first (G6). reseller_only guard deleted; any command using
  it re-tagged root_only or operators_only per intent.
- Transition: dispatcher honors old in-file markers until every command
  carries a resolved role gate; a lint reports commands still lacking one.

## Open (fold into the G11 work package)
- Exact operator command allow-list (which subset of root's commands).
- Whether operators are farm-wide or scoped to specific clusters/hosts.
