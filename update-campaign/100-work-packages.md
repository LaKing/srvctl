# 100 — Phase C work-package sequence (Stage 2 execution backlog)

Gate: plans approved 2026-07-05 (user: "start the campaign, plan and execute
as you see fit"). Recorded in 000-INDEX Stage gate record.

Execution rules (from 000-PROMPT + the Stage-2 preconditions in 000-INDEX):
- Branch v4, in-place (D1); never mutate /usr/local/share/srvctl (running v3).
- Each package: verify before commit; keep the CLI working throughout (D1
  step-by-step). Draw FIXMEs from 021, re-verify file:line at HEAD.
- Build everything, then VM-test, then live (D26).

## Dependency-ordered sequence

### Foundation (datastore + runtime)
- **WP-A ✅ DONE (2026-07-05, commit 615f1f8)** — datastore STORAGE ENGINE:
  file-per-entity, atomic rename, single locked writer, validate-on-write,
  git-versioned (014). modules/datastore/lib/store.mjs + migrate.mjs +
  selftest/store.test.mjs (15 tests pass incl. cross-process concurrency,
  lossless migration round-trip, stale-lock steal, validate-under-lock, and
  no partial writes / no post-validation mutation leaks from transactions).
  Additive — live verb path untouched (that's WP-C).
- **WP-B — part 1 ✅ DONE** (addressing/identity): derive.mjs = 14 pure
  functions (uid/br/gw/interface/br_host_ip/bridge/user_id/user_ip_match/
  hostnet/host/host_ip/reseller/http_port/https_port) over an explicit
  context, faithful v3 port (quirks preserved, FIXMEs marked). 29 snapshot
  tests pass. selftest/run.sh runs the whole datastore suite (44 tests).
  - **WP-B — part 2 (pending)**: config-string generators (resolv_conf,
    /etc/hosts, nspawn, firewall, mapped_ports, relaydomains) — snapshot vs
    v3 output; folds into WP-C wiring.
- **WP-C** — wire the VERB API (get/put/out/cfg/del/new/add) + derivations
  onto the engine; byte-identical output + exit codes (main.js contract);
  run the datastore on file-per-entity behind the existing bash wrappers.
  Fixes the duplicate-ADD race and the dead RO guard in the process.
- **WP-D** — bash FRONT DOOR + command index: light srvctl.sh/init.sh/
  commonlib.sh; node builds a cached command/help index (kills the
  hint_on_file grep storm) — the G1 dispatch win. Preserve hook contract
  (010/011): fixed startup sequence + explicit run_hooks; sourced scope.

### Permissions & user model
- **WP-E** — G11 permission model: roles root/operator/user; `sc` everywhere
  for everyone; role-filtered `sc` listing; root_only + operators_only +
  owner checks; fix the always-true [[ $SC_UID0 ]] gates. Role/owner from
  the datastore.
- **WP-F** — G6 reseller removal: drop reseller_only, the a..z pre-created
  accounts, reseller_id derivation; per-server user inventory first.

### Networking / certs / mail (deprecations)
- **WP-G** — G8 ZeroTier: self-hosted controller; 10.16.x.y range;
  zerotier module replaces openvpn hostnet + usernet; repoint nfs/ssh/
  datastore/named consumers 10.15→10.16 one at a time; remove openvpn after.
  Absorb the user's add-zerotier.sh (containers/external).
- **WP-H** — G7 wildcard certs: all-wildcard via DNS-01/RFC2136 against the
  primary of two authoritative DNS servers; drop the expired static CA
  append; retire acme http-01 (port 1028). Couples to named redesign
  (primary+secondary for all clusters).
- **WP-I** — G9 mail proxy: dovecot proxy PoC FIRST (993/995 by user@domain,
  wildcard TLS, forwarded creds, AND postfix SMTP AUTH via testsaslauthd —
  017 open risk). Then the mailproxy module; remove perdition after.

### Removals / cleanup
- **WP-J** — G4 gluster removal: de-gluster datastore+static hooks FIRST
  (019 ordering constraint), then drop the module; nothing replaces it.
- **WP-K** — G5 gui removal: nuke the gui module; keep make_commands_spec as
  JSON metadata (cockpit postponed).
- **WP-L** — cross-cutting FIXME sweep from 021 by severity (the security
  HIGHs first: codepad plaintext password, letsencrypt expired CA,
  sudoers-NOPASSWD, vncproxy injection, ssh key-revocation, datastore
  traversal), each with its own verify.

### Validation & rollout
- **WP-M** — VM test cluster: stand up a virtual mirror; scripted
  side-by-side vs captured v3 behavior for the command inventory + the
  deprecation cutovers.
- **WP-N** — live rollout: per-server inventory → backup → in-place upgrade
  → observe → next; dated report each (013).

Order is a guide, not a straitjacket — WP-A..D are strictly sequential
(each builds on the last); E onward can interleave once the foundation is
solid. Each WP gets its own numbered doc (101+) when started, or is tracked
inline here for small ones.
