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
    - **WP-C — dispatcher step 2 ✅ DONE**: main.mjs now reads/writes via
      store.mjs (file-per-entity, atomic + locked). Readonly is enforced in
      the writer on the EFFECTIVE variable SC_DATASTORE_RO_USE (the step-1
      deferred fix); git:false (bash datastore_push still commits — libs/
      gitlib.sh). The verb harness migrates its monolithic fixture to
      per-entity and compares mutation effects SEMANTICALLY (entity maps,
      order-independent); stdout/stderr/exit stay byte-exact.
      - **v4 ITERATION CONTRACT (intentional, general — NOT just 3 cases):**
        store.readAll() returns each type's keys **lexicographically sorted by
        id**. This intentionally REPLACES v3's monolithic-JSON insertion order
        for all entity-map iteration — cluster/user/container listings and
        generated /etc/hosts ordering — and any FUTURE cluster generator/list
        that iterates entity maps inherits it. v3's insertion order was
        incidental storage behavior, not a domain contract. The current
        fixture exposes exactly 3 stdout diffs (get-cluster user_list /
        container_list / etc_hosts); those 3 golden cases were updated
        explicitly to the sorted order. NO .order index was added (rejected:
        a second state file + migration/maintenance/concurrency/drift surface
        to preserve incidental order).
      - Caveat (future data-quality check, not .order): /etc/hosts entry order
        is normally irrelevant, but DUPLICATE generated hostnames/aliases can
        make order observable. Treat duplicate generated hostnames as a v4
        validation/data-quality check, not an ordering mechanism.
      - CONCURRENCY FIX (Codex finding, high): the pre-lock snapshot let
        concurrent mutating verbs allocate duplicate ips/user_ids/uids/
        host_ports (reproduced: 20 parallel new-container → 10.20.0.2 ×8).
        Fixed — every mutating verb now runs fresh-read + allocate + write
        inside ONE store.transaction() lock (reads stay lock-free).
        selftest/concurrency.test.mjs proves it: 20 parallel new-container /
        new-user / add_mapped_port → zero duplicate allocations, no lost
        writes. Datastore suite now 197 checks.
    - **WP-C — step 2b HARDENING (Codex, 3 high findings fixed)**:
      - SECRETS: `git add -A` staged users/<name>/ keys (id_ecdsa/.password)
        and cert/ keys. Fixed with defense-in-depth: datastore_push stages
        `-- hosts users containers` ONLY (cert/, .monolithic-backup never
        seen), AND .gitignore excludes `users/*/`, `cert/`, `.monolithic-
        backup/` (keeps users/<name>.json). init guarantees the 3 type dirs
        exist so the pathspec can't error on an empty type.
      - .gitignore now written IDEMPOTENTLY (not only on fresh git init), so
        upgraded v3 repos also get the new exclusions.
      - MIGRATION LOSS: migrate.mjs now requires ALL THREE monolithic files
        (present containers.json='{}' ok; MISSING = loss → hard fail, exit 1,
        transaction rollback = nothing written, monolithic left in place).
        Was: a partial hosts-only store silently migrated to users:0/
        containers:0. store.test updated to assert the hard-fail contract.
      - Verified: pathspec+gitignore stage only entity json (no secrets/
        backup); partial store fails clean; suite 197.
    - **WP-C — step 2b (bash wiring) ✅ DONE (locally verified)**:
      - gitlib.sh datastore_push: `git add ./*.json` → `git add -A -- hosts
        users containers` (constrained pathspec — see the hardening bullet
        above; commits the entity tree, never secrets/cert/backup).
      - datalib.sh: init_datastore_install now seeds the v3 monolithic sources
        then converts to per-entity; migrate_datastore_to_per_entity() runs
        migrate.mjs in-place (idempotent; archives hosts/users/containers.json
        to .monolithic-backup after success); init_datastore triggers it when
        the per-entity dir is absent or monolithic files remain, RW+root only,
        and EXPORTS SC_DATASTORE_DIR + SC_DATASTORE_RO_USE.
      - migrate.mjs CLI now git:false (bash owns the commit).
      - commonlib.sh set_permissions: per-entity type dirs → 755, entity json
        → 644 (non-root `sc get` reads, as v3's *.json were).
      - Verified locally: fabricated monolithic → migrate → per-entity →
        main.mjs reads correctly; SC_DATASTORE_RO_USE=true → main.mjs refuses
        writes (LIB-ERROR 112); users/<u>/ key dirs coexist (store reads only
        *.json); bash -n + shellcheck clean; suite 197.
      - NEEDS VM-TEST (D26) before live: end-to-end update-install migration on
        a real server; the FULL per-entity permission model (keys under
        users/<u>/, cert/); the RO_DIR=gluster coupling (pre-init.sh) — RO mode
        + RO_DIR must be reworked with G4 (gluster removal), after which
        SC_DATASTORE_RO_USE is effectively always false.
      - Deferred (explicit golden-updating): collapse the duplicate-ADD
        double-write to a single write (alters stdout: two "wrote" lines → one).
- **WP-D** — bash FRONT DOOR + command index: light srvctl.sh/init.sh/
  commonlib.sh; node builds a cached command/help index (kills the
  hint_on_file grep storm) — the G1 dispatch win. Preserve hook contract
  (010/011): fixed startup sequence + explicit run_hooks; sourced scope.
  - Measured baseline (dev box, warm): `sc help` = ~0.125s and forks ~190
    external procs (76 grep + 38 sed + 38 head + 38 basename) — 4-5 per
    command file × 38 files; bare `sc` dispatch ~0.087s.
  - **WP-D — parser ✅ DONE (isolated, tested)**: modules/srvctl/lib/
    commandindex.mjs parses a command file's help metadata (hint/@en,
    syntax/@@@, dynamic/&&&, help/&en lines, root_only/hs_only/reseller_only)
    + buildIndex() CLI. selftest/commandindex.test.mjs is a DIFFERENTIAL vs
    the actual commonlib.sh grep pipelines over all 38 real command files:
    190/190 identical, incl. the load-bearing whole-file `## &&&` (add-ve at
    line 13) and head-10/head-20 window semantics.
  - **WP-D — SANDBOX HARNESS ✅ DONE** (modules/srvctl/selftest/sandbox/):
    runs the REAL srvctl.sh help path inside an unprivileged user+mount+uts
    namespace with every live srvctl path (/etc/srvctl, /var/local/srvctl,
    /var/srvctl3, /root, /var/log) bind-shadowed by sandbox temp dirs +
    checksum guard. This is what lets bash/runtime changes be tested on the
    dev box safely (the datastore-migration hazard that blocked it is now
    physically impossible in-namespace). Deterministic fixture modules;
    committed golden (golden/help.txt); skips cleanly where ns unavailable.
  - **WP-D — help-path wiring ✅ DONE (`sc help`)**: commandindex.mjs gains a
    `--bash` mode; commonlib.sh build_command_index() parses ALL command
    files in ONE node call into SC_IDX_HINT/SC_IDX_HELP; help_on_file reads
    the index (grep fallback for single `sc help CMD` / unindexed paths);
    help_commands builds it once for the full listing. PROVEN:
      · harness golden byte-identical (fixtures)
      · real-module DIFFERENTIAL byte-identical — `sc help` grep-path (git
        HEAD) vs index-path over ALL 38 real command files: 240/240 lines
        identical (in-sandbox, both commonlib versions)
      · fork storm eliminated: 190 external procs (76 grep+38 sed+38 head+38
        basename) → 0 of those + 1 node call (shim-measured in-sandbox)
      · shellcheck unchanged (8); hint_on_file (bare `sc`) left on grep.
  - **WP-D — remaining**: wire hint_on_file (bare `sc`, needs runtime dynamic
    `## &&&` exec + permission filter kept; the F-line syntax/dynamic/perms
    fields already emitted); optional persisted/cached index (mtime-keyed)
    so the node call is amortized; light srvctl.sh/init.sh dispatch. Do
    per-command perf timing on real hardware in the VM cluster (WP-M/D26).

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
