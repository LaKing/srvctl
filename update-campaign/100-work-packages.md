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
  tests pass. Store+derive subtotal: 44 checks.
  - **WP-B — part 2 ✅ DONE**: pure text/config generators → generators.mjs
    (resolv_conf, hosts, ethernet, ethernet_network, quota, nspawn+helpers,
    br_netdev, br_network, firewall_commands, mx, domains, useruids, user_uid,
    cluster_etc_hosts/relaydomains/host_keys/lists, user_container_list,
    normalize_*). generators.test.mjs = 77 checks: LIVE DIFFERENTIAL vs v3
    lib.js return values over a rich fixture (aliases/altnames/subdomains/
    mapped_ports/dotless/gsuite/mail), + resolv_conf with controlled HOSTNAME,
    + useruids over injected passwd/group. Found+preserved v3 quirks (uid-0
    root skipped in useruids; hardcoded 10.15 in etc_hosts) as FIXME(v4).
    Datastore suite reached 182 checks. The v3 reference is frozen in
    selftest/golden/generators.json (71 normalized entries); normal
    verification no longer depends on lib.js, only `--record` does.
- **WP-C — golden-master harness ✅ DONE** (precondition, per user):
  selftest/verbapi.test.mjs + golden/fixture/*.json + golden/golden.json
  freeze the live v3 main.js verb contract — 61 cases (get/out/cfg/del/put/
  add/new across container/user/reseller/host/cluster + arg/dispatch errors
  + mutation file-effects), stdout+stderr+exit pinned, os.hostname()
  normalized, and child-spawn failures hard-fail instead of recording empty
  output. Deterministic (full suite + 3 direct repeats). Cross-checks WP-B:
  golden derivation outputs match derive.mjs exactly. Full datastore suite:
  105 checks. `get container C resolv_conf` is intentionally excluded from
  the v3 golden: v3 hardcodes os.hostname() and crashes under a portable
  fixture whose host list does not include the test machine, pinning a
  fixture artifact rather than a production contract. Cover resolv_conf in
  the generator snapshots with explicit ctx.HOSTNAME.
- **WP-C — mutator pure port ✅ DONE**: mutators.mjs covers the write
  state-transitions and allocation helpers (new_user/reseller/container,
  container_update_ip, container_add_mapped_port, next user/ip/uid/host-port)
  as pure functions that return records/values for the dispatcher to persist.
  mutators.test.mjs = 8 checks, including five frozen v3 resulting records in
  selftest/golden/mutators.json plus v4-only mapped-port allocation edge cases.
  Full datastore suite now 190 checks. Normal verification no longer depends
  on lib.js; only `--record` does while v3 is still present.
  - **WP-C — dispatcher step 1 ✅ DONE**: main.mjs reimplements the v3
    verb API on derive/generators/mutators, reading/writing the MONOLITHIC
    three-file datastore. main.js is now a CJS cutover shim that
    dynamic-imports main.mjs (bashlib + the verb harness keep running
    unchanged); v3 dispatcher logic is preserved in git history, lib.js kept
    for --record. The 61-case verb golden is byte-exact (61/61):
    stdout/stderr/exit AND mutation file contents. Reproduced v3's async
    write-msg ordering (deferred "wrote X.json" flush after sync output) and
    the cfg trailing-exit() (return_value undefined -> exit()=0). The
    duplicate-ADD double-write is REPRODUCED verbatim (two "wrote" lines) to
    hold the golden. Monolithic load/write CONTRACT matches v3 (per Codex
    audit): all three JSON files REQUIRED (missing → LIB-ERROR 112, not an
    empty map); writes wrapped → LIB-ERROR 112 on failure (not a Node stack);
    the SC_DATASTORE_RO guard is reproduced VERBATIM — but note it is dead in
    practice (bash sets SC_DATASTORE_RO_USE, never SC_DATASTORE_RO), so RO is
    NOT effectively enforced yet. Fixing the guard to the effective variable
    is deferred to step 2 (store.mjs's writer-level RO). Full datastore
    suite: 190 checks.
    - **WP-C — dispatcher step 2 (next)**: swap main.mjs's monolithic backend
      to store.mjs file-per-entity; adapt the verb harness's mutation
      comparison from raw monolithic bytes to semantic entity maps (stdout/
      exit stay byte-exact). Then optionally collapse the duplicate-ADD to a
      single write as an EXPLICIT golden-updating change (it alters stdout:
      two "wrote" lines -> one).
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
