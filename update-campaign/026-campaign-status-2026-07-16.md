# 026 — Campaign status (2026-07-16)

The update campaign is technically healthy but not release-ready. The
repository is clean, pushed, and synchronized with origin/v4 at version
4.0.0.7 (d0c9717).

| Area | Status |
|---|---|
| WP-A–C: datastore/runtime foundation | Complete |
| WP-D: front door and command index | Core work complete; persistent caching, final runtime slimming, and real-hardware performance remain |
| WP-E: permission model | Substantially complete; separate security-audit blockers remain |
| WP-F: reseller removal | Phases 0–2 built; production migration and Phases 3–5 remain |
| WP-G: ZeroTier | Not started; OpenVPN remains |
| WP-H: wildcard certificates | Partially complete: selection, distribution, and TLS consumer propagation exist; DNS-01 issuance is not implemented |
| WP-I: mail proxy | Not started; Perdition remains |
| WP-J: Gluster removal | Not started; module remains |
| WP-K: GUI removal | Not started; module remains |
| WP-L: FIXME/security sweep | Partial; significant backlog remains |
| WP-M: VM validation | Not completed |
| WP-N: live rollout | Not started as a controlled campaign |

## The immediate planned work is still WP-F

1. Run the Phase 2 reseller migrator on every production host — dry-run first.
2. Re-tag `reseller_only` commands to `operators_only`.
3. Remove reseller super-ownership from `owner_only`.
4. Remove the remaining reseller model, commands, derivations, and SSH-key
   machinery.

## Important status problems

- `update-campaign/024-where-we-stand.md` §5 was stale: it still said Phase 2
  awaits Phase 0 output, although the migrator is now built and tested.
  (Corrected alongside this status doc.)
- `update-campaign/100-work-packages.md` WP-F entry was also behind the actual
  implementation. (Corrected alongside this status doc.)
- The five P0 security/release items in `TODO.md` remain open.
- Version 4.0.0.7 deleted all three example configuration files, while the
  README and installation documentation still require them
  (`example-conf/data/.` and `example-conf/clusters.json.example`). A clean
  installation currently cannot follow the documented procedure.
  **RESOLVED same day, by changing the documentation**: the install docs no
  longer reference `example-conf/`; complete validated templates for
  clusters.json / branding.conf / ca.conf are inline in
  `documentation/documentation.md` (Initial Configuration), and README.md /
  README.txt point there.

## Bottom line

The v4 foundation and recent topology/DNS work are strong and tested, but
WP-F must finish, the P0 audit findings must be resolved, and VM validation
completed before live rollout. (The example/documentation mismatch was
resolved the same day by inlining the templates into the documentation.)
