# 012 — v4 permission model (G11) — DRAFT for review

Status: DRAFT written session 1 (autonomous). Not approved.

## v3 reality (commit 988c38c)

Enforcement is per-script convention, and admittedly unfinished:

- `root_only` (modules/srvctl/libs/authlib.sh:3) — exits 44 unless UID 0;
  also leaks a stray `echo "SC_UID0 true"` into every root command's output.
- `reseller_only` (authlib.sh:14) — "reseller" = any ONE-CHARACTER username
  (the a..z pre-created accounts; scheduled for deprecation, G6).
- `authorize` (authlib.sh:32) — a stub: prints "DEV (Authorization
  implementation not complete.)" and returns success for non-root. Every
  command relying on it is effectively unprotected beyond file-level sudo.
- `sudomize` (authlib.sh:46) — re-execs via sudo, but passes all arguments
  as one collapsed string ($SC_COMMAND_ARGUMENTS = "$*"), and its error
  path `exit $?` actually exits with debug's status (0), masking failures.
- Help visibility ≠ permission: hint_on_file greps root_only/hs_only/
  reseller_only markers only to HIDE hints (commonlib.sh:218-223);
  execution is gated separately (or not at all).
- Root commands are logged to /var/log/srvctl-root.log (init.sh:145).

## v4 proposal

One enforcement point: the dispatcher checks a declared policy before any
command code runs. No per-script guard calls to forget.

- Command policy declared in the command's metadata (with the help meta):
  `role: root | user | any` plus `scope: own` for resource-bound commands
  (a user may act on containers/sites they own; ownership lives in the
  datastore, which v4 moves to srvctl-modules/datastore, G2).
- Roles: `root` (host admin) and `user` (owns VEs). The reseller role is
  removed (G6); nothing else inherits its 1-char-username magic. If
  delegation is needed later, an explicit `operator` role with a grants
  list in the datastore — not username-shape heuristics.
- `sudomize` semantics survive as a dispatcher feature (auto-sudo for
  root-role commands when the caller may escalate), with argv passed as an
  array — fixing the collapse bug by design.
- Audit: every privileged command logged (keep srvctl-root.log format), and
  denials logged with the failing policy.
- Cockpit (G5) authenticates via PAM as the same Unix users; it calls sc
  with the caller's identity, so policy enforcement stays in one place.

## Migration notes

- Transition: dispatcher honors old in-file markers (root_only etc.) until
  every command carries declared policy; a lint in update-install reports
  commands still lacking one.
- The a..z reseller accounts are NOT touched by the polish pass; their
  removal is a Stage-2 work package with a per-server user inventory first
  (G6, G13).

## Open questions (for the user)

1. Are there non-root human admins today on the ~5 servers, or is
   everything root + end-users?
2. Should end users be able to run any sc commands on the HOST at all in
   v4, or only inside their containers / via cockpit?
3. Is per-user ownership already recorded somewhere authoritative
   (datastore users.json / default-users.json), or must it be
   reconstructed during migration?
