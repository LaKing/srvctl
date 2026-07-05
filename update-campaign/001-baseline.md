# 001 — v3 performance baseline (G1 yardstick)

Measured 2026-07-05 on host `v4-devel`, srvctl 3.2.5.9 running from
/usr/local/share/srvctl (bash time builtin, warm cache, non-root user).

| Command | real (s), 3 runs |
|---------|------------------|
| sc help | 0.165, 0.120, 0.120 |
| sc (no args, exit 1) | 0.083 |

Observations:
- Bare dispatch is ~0.12s warm — not the pain point on this host.
- The perceived slowness of srvctl3 therefore likely lives in heavier
  commands (container operations, regenerate, backup, list operations that
  shell out per-container) and in cold-cache/many-container conditions on
  production hosts.
- TODO (Phase A, needs a host with real containers / the user's guidance):
  time `sc regenerate`, container list/status commands, add-ve dry paths;
  profile init.sh module-condition sourcing (37 modules × source at init).
- G1 measure for v4: keep dispatch <50ms and make the heavy commands
  measurably faster; re-measure this table on the same host after the mjs
  core lands.
