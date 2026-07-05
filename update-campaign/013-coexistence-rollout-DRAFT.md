# 013 — v3/v4 coexistence and production rollout (G13) — DRAFT for review

Status: DRAFT written session 1 (autonomous). Not approved.

## Facts the plan is built on (from modules/srvctl.md fact sheet)

- `sc update-install` does NOT update srvctl code. There is no git pull in
  the flow; code lands on servers out-of-band (bootstrap pop.sh clones to
  /usr/local/share/srvctl; dev boxes run /bin/pop at every root TTY call).
  So v4 cannot "ride" a self-update mechanism — code delivery is a manual,
  controllable step. That is good for us.
- `update-install` has heavy side effects: unconditional full `dnf update`,
  SELinux disabled, networkd rewrite (may drop NetworkManager), ssh-keyscan
  of cluster hosts, all modules' install hooks. A v4 migration must never
  trigger these implicitly.
- The running install is a plain copy, not a git checkout, on this dev box;
  production layout to be verified per server in the inventory step.

## Coexistence mechanism (proposal)

1. v4 code is delivered as a git checkout at /usr/local/share/srvctl4
   (branch v4 tag), never touching /usr/local/share/srvctl (v3).
2. A `sc4` symlink (/bin/sc4) points at the v4 entry point. Both CLIs
   coexist; v3 remains the default `sc`.
3. Shared state (/etc/srvctl, datastore, /srv containers) is owned by ONE
   side at a time. v4 runs in read-only "shadow mode" first: every v4
   command that would write refuses unless SC4_ACTIVE=true.
4. Verification per server: scripted side-by-side comparison of read-only
   command outputs (sc X vs sc4 X) for the command inventory; then
   selected write-path commands on a disposable test container.
5. Cutover per server: set SC4_ACTIVE, repoint /bin/sc and /bin/srvctl to
   v4, keep /bin/sc3 pointing at v3 for instant rollback.
6. Rollback = repoint symlinks back to v3 (v3 is never modified). Datastore
   schema must therefore stay v3-compatible until ALL servers are cut over
   (no destructive datastore migrations in v4.0).

## Rollout order (~5 production servers + this dev box)

1. v4-devel (this host) — everything is tested here first.
2. Server inventory step per production host BEFORE any v4 code lands:
   srvctl version, module list (SC_USE_*), container list, custom commands
   in /root/srvctl-includes and user includes, local config drift, disk
   space, backup freshness. Filed as a dated report in this folder.
3. Least-critical production server first (user picks the order); observe
   for an agreed soak time (suggest: days, not hours) before the next.
4. One server at a time, never two in flight; each gets a dated migration
   report (steps run, outputs, anomalies, rollback tested yes/no).

## Explicitly deferred to the user

- The order of the 5 servers and the soak time between them.
- When (if ever) v3 gets deleted from a cut-over server (suggest: only
  after all servers run v4 through a full backup cycle).
- Whether v4.0 keeps the update-install side effects (dnf update, SELinux
  disable) or splits them into explicit subcommands (recommended: split;
  behavior change, needs sign-off).
