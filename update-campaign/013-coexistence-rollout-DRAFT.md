# 013 — v4 upgrade & rollout (G13) — decisions folded (D1, D6, D26, D27)

Status: direction DECIDED 2026-07-05. This SUPERSEDES the earlier
"side-by-side coexistence" draft — the user chose an IN-PLACE, step-by-step
upgrade (D1, D27), not v3/v4 side-by-side.

## Decisions

### In-place, one `sc`, upgraded step by step (D1, D27)
- v4 continues in the SAME repo at /srv/srvctl-project, **version 4.0.0.0**,
  the SAME entry point (`/bin/sc`, `/bin/srvctl`). There is ONE `sc`.
- v3 and v4 do NOT coexist. No `srvctl4` install dir, no `sc4`/`sc3`
  symlinks. The single install is upgraded incrementally: modules/commands
  move to the bash-shim + .mjs shape one at a time, each keeping the CLI
  working throughout.
- This is safe precisely because the polish pass kept every command
  functionally identical — v4 replaces internals under a stable CLI surface.

### Build everything, then VM-test, then live (D26)
- Sequence: implement all the planned work (Phase D) → run VIRTUAL tests
  (VM cluster mirroring prod) → apply to live servers thereafter.
- So the rollout is NOT trickle-per-server-during-development; it's
  build-and-verify-in-VMs first, live cutover as a later, deliberate phase.

### update-install side effects (D6)
- update-install must NOT run `dnf update` itself. Instead it CHECKS that
  the system packages are already up to date; if not, it exits with an error
  telling the operator to bring dnf up to date first.
- SELinux: for now, v4 may REQUIRE SELinux disabled (as v3 does). But every
  component must be written so it WILL work once SELinux is switched on —
  target: enable SELinux after the project stabilizes. Treat "works with
  SELinux enforcing" as an acceptance criterion for each module, tracked as
  a standing task, even while disabled is the current baseline.

## Production continuity (still normative — G13)
- Live servers stay online. Read-only probes always allowed; any
  state-changing test names its rollback.
- Because there is one `sc` and no side-by-side fallback, the VM-test gate
  (D26) is what de-risks live cutover — it replaces the "instant symlink
  rollback" the coexistence design would have given. Live cutover therefore
  requires: a verified backup per server, the VM test suite green, and a
  documented per-server rollback (restore from backup).
- No irreversible step (data deletion, module removal, cert/mesh cutover)
  without a verified backup and a tested rollback. Deprecations (G4/G6/G8/G9)
  run as: install replacement → verify → disable old → observe → remove old.

## Per-server rollout (live phase, after VM tests pass)
1. Per-server inventory BEFORE upgrade: srvctl version, module list
   (SC_USE_*), container list, custom commands in /root/srvctl-includes and
   user includes, config drift, disk, backup freshness. Dated report in this
   folder.
2. Verified backup (incl. the datastore git tag/tarball, per 014).
3. Upgrade `sc` in place; run `update-install` (which now only VERIFIES dnf
   is current, per D6); regenerate.
4. Observe; if broken, restore from backup.
5. One server at a time; dated migration report each.

## Open (fold into rollout work package)
- The VM test-cluster definition (how many nodes, what it mirrors).
- Server order for the live phase (user picks when we get there).
- The datastore layout migration (monolithic→file-per-entity, one-shot per
  server) is specified in 014.
