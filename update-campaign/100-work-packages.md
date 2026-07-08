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
    three-file datastore. (Follow-up: the CJS cutover shim main.js was
    REMOVED — bashlib.sh + the verb harness now spawn `node main.mjs`
    directly. v3 dispatcher logic is preserved in git history; lib.js kept as
    the v3 --record oracle only.) The 61-case verb golden is byte-exact (61/61):
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
    line 13) and then-current head-10/head-20 window semantics. WP-E.2.b later
    changed permission-marker semantics to whole-file line-anchored guard calls.
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
  - **WP-D — hint_on_file wiring ✅ DONE (bare `sc`)**: build_command_index
    now fills SC_IDX_SYNTAX/DYNAMIC/ROOT/HS/RES too; hint_on_file reads them
    (permission filter from the booleans; `## &&&` still executed at runtime),
    grep fallback kept; hint_commands builds the index once (mirroring its
    SC_USE filter + command.sh). Two bugs the harness caught + fixed:
      · fixture module names with HYPHENS → invalid SC_USE_<NAME> identifiers
        → hint_commands' `${!tvhc}` filter silently listed nothing (real
        modules have no hyphens; `sc help` hid it by skipping the filter).
        Renamed harness-a/b → harnessa/b.
      · the `F` line was TAB-delimited; `read` collapses consecutive tabs
        (IFS-whitespace), shifting empty syntax/dynamic fields → wrong labels.
        Switched to `\x1f` (non-whitespace). Parser test now enforces the
        "present @@@/&&& ⇒ non-empty value" invariant (266 checks).
      PROVEN byte-identical: bare-`sc` fixture differential 2/2 (SC_HOSTNET
      set: dynamic exec + all shown; unset: hs_only filtered) AND real-module
      bare-`sc` differential (82/82 lines, incl. add-ve's live `## &&&`).
      Forks: 280 (120 head+120 grep+40 basename) → 0 + 1 node call.
      Committed golden/bare.txt. root_only/reseller_only FILTER firing needs
      SC_UID0=false (non-root) which the userns can't provide (uid 0); the
      booleans are proven == grep by commandindex.test, and the filter is a
      mechanical substitution — empirical non-root run is a VM-cluster item.
      Audit follow-up: commandindex.test now includes module `command.sh`
      default-command files too (bare `sc` indexes them); this closes the
      committed regression-test gap left by the initial 38-file parser pass.
  - **WP-D — remaining**: optional persisted/cached index (mtime-keyed) so the
    node call is amortized across invocations; light srvctl.sh/init.sh
    dispatch. Per-command perf timing on real hardware (VM cluster, WP-M/D26).

### Permissions & user model
- **WP-E** — G11 permission model: roles root/operator/user; `sc` everywhere
  for everyone; role-filtered `sc` listing; root_only + operators_only +
  owner checks; fix the always-true [[ $SC_UID0 ]] gates. Role/owner from
  the datastore.
  - **WP-E.1 — mechanical security correctness ✅ DONE** (user-scoped: NO
    role model, NO authorize-deny, NO hs_only/ve_only patch — those are
    WP-E.2). A permission-model map (Explore agent) found 12 latent bugs;
    E.1 fixes the mechanical ones, enforcing for real:
      · 5 always-true `[[ $SC_UID0 ]]` gates → `$SC_UID0` (destroy-ve,
        remove-ve, backupcontainerlib, http-redirect, override-in-address) —
        their "access denied" branches were dead code.
      · run_command dispatch precedence (commonlib.sh): `&&` bound tighter
        than `||` so only `new` was root-gated; now WRITES (new/put/cfg/del/
        add) require root, READS (get/out) stay open (internal non-root reads
        use the bashlib wrappers, not this path).
      · access-denied bare `exit` (status 0) → `exit 44` in all of the above
        + https-redirect + map-port (finding #8 class).
      · removed the `root_only` `echo "SC_UID0 true"` stdout leak.
    PROOF: selftest/authgate.test.sh — a deny/allow probe (must run non-root)
    with datastore verbs + destructive ops stubbed, so it runs safely against
    the pre-fix tree and shows the bugs. 27/27 after fixes (non-owner DENIED
    exit 44 + no action for all 7 commands; owner escalates; non-root raw
    writes blocked, reads open). Harness + datastore suites green; shellcheck
    unchanged. reseller_only kept transitional (removed in WP-F).
  - **WP-E.2 (next)** — the root/operator/user model on top: SC_ROLE resolved
    once from the datastore (uid0→root; users/<name>.json role:operator→
    operator; else user), operators_only + owner_only guards, unify the
    listing filter with the guards, sudomize argv-as-array. CAVEAT (user):
    hs_only/ve_only need a CENTRALIZED, always-loaded auth signal — ve_only
    lives in containers/libs but `containers` is disabled inside a VE while
    `usersonve` is enabled there, so VE commands can call a guard from an
    unloaded module. Centralize the guards in srvctl auth (or load explicitly).
    Twin http/https-redirect should share one auth helper. Audit follow-up:
    do not treat E.1 as complete authorization. The non-denying `authorize`
    stub still lets some commands run preliminary work before a later guard;
    concrete case: non-owner `recreate-ve` reaches `systemctl stop` before
    `backup_ve` can deny. Also, `map-port` still denies direct root unless
    `SC_USER` is the container owner/reseller; E.1 only made that denial
    nonzero. WP-E.2's root/operator/user + owner_only helpers must fix both.
  - **WP-E.2.a — owner_only guard ✅ STARTED (recreate-ve + map-port)**:
    added `owner_only <type> <id>` to modules/srvctl/libs/authlib.sh (always
    loaded, check-BEFORE-act): root passes (everything for everyone), owner/
    reseller escalates via sudomize, else deny 44. Rewired the two flagged
    residuals to it: recreate-ve (now denies a non-owner BEFORE ssh mongodump
    + `systemctl stop`) and map-port (root now allowed regardless of
    ownership; dropped the unconditional sudomize). authgate.test.sh extended
    to 32/32 — for both: non-owner DENIED with NO action (check-before-act),
    owner escalates, root-non-owner ALLOWED.
  - **WP-E.2.a — owner_only rewire COMPLETE (all 8 owner commands) ✅**: the
    other six now use owner_only too — http-redirect, https-redirect (twins
    now share owner_only, dropping the divergent `[[ $USER == root ]]`),
    override-in-address, backup-ve, destroy-ve, remove-ve. The two large ones
    had their action dedented out of the old `if $SC_UID0` wrapper (functional
    edit, then a range `sed` dedent, bash -n after each). authgate.test.sh at
    40/40: for every owner command non-owner DENIED (exit 44) with NO action
    (check-before-act), owner ESCALATES, root-non-owner ALLOWED; + dispatch
    + backup_ve lib gate. Strict shellcheck (no -x) clean on all touched files.
    NEXT: sudomize argv/status (owner_only now depends on it), then E.2.b
    (SC_ROLE/operators_only/listing unify).
  - **WP-E.2.a — sudomize argv/status ✅ (status active; argv ready)**:
    authlib.sh sudomize now (a) exits with sudo's REAL status — was
    `exit $?` after a `debug`, always 0, masking failed re-execs — and (b)
    calls sudo DIRECTLY (not via `run`, whose unquoted $* re-split argv) with
    `"${SC_ARGV[@]}"` when set, else the old space-joined SC_COMMAND_ARGUMENTS.
    authgate.test.sh Part C (45/45 total): spaced arg preserved, sudo status
    propagated (7→7), fallback re-execs. The status fix is LIVE now; the argv
    fix is INERT until srvctl.sh exposes `SC_ARGV=("$@")` — one line I did NOT
    add because srvctl.sh is the user's WIP. **ACTION for user: add
    `SC_ARGV=("$@")` in srvctl.sh (next to `SC_COMMAND_ARGUMENTS="$*"`).**
  - **WP-E.2.a — owner_only lookup-error propagation ✅ (audit fix)**: owner_only
    ignored `get`'s exit status, so a DATASTORE ERROR (or entity-missing) on the
    user/reseller lookup fell through to a misleading `err "no access"; exit 44`.
    Now it checks each `get`: exit 0 (value) or 100 (optional absent) proceed;
    anything else emits "Cannot verify ownership — datastore lookup failed ($rc)"
    and exits with that code (not 44). authgate.test.sh (48/48): a get error
    (112) PROPAGATES as 112 with no action; a 100 (optional-absent reseller)
    stays a clean 44 deny. Verified the test fails pre-fix (got 44, want 112).
    With this, E.2.a is complete pending the user's SC_ARGV line.
  - **WP-E.2.a — DONE**; SC_ARGV=("$@") added to srvctl.sh (left UNCOMMITTED,
    user's WIP) so sudomize's faithful-argv path is now live.
  - **WP-E.2.b MODEL (agreed with user)**: explicit per-command class marker,
    proven per role×class (no name-inference). Classes: root_only / owner_only
    <res> / operators_only / everyone(default). Access: root=all;
    operator=operators_only+everyone (does NOT bypass owner_only); user=
    everyone+owned owner_only; non-owner denied owner_only. Host-scoped role.
  - **WP-E.2.b-1 — role MECHANISM ✅ (enforcement proven)**: authlib.sh gains
    sc_role (memoized SC_ROLE: uid0→root; local datastore role=operator→
    operator; else user — absent/error→user, never escalates) and
    operators_only (root+operator, exit 44). selftest/authfixtures/{everyone,
    rootonly,operatorsonly,owneronly}.sh = one command per class; authgate.test
    Part D proves the full role×class ENFORCEMENT matrix (61/61 total,
    verified a broken guard fails the matrix). Strict shellcheck clean.
    Audit fix: sc_role now initializes its role cache inside authlib.sh so an
    inherited `SC_ROLE=operator` environment variable is ignored; matrix adds
    an explicit spoof-denied cell.
  - **WP-E.2.b-1b — LISTING filter unified for bare `sc` ✅**: commandindex.mjs
    now parses the operators_only marker (new F-line field; differential
    280/280) and commonlib build_command_index reads it into SC_IDX_OPS.
    hint_on_file's filter (both indexed + grep-fallback paths) now mirrors the
    guards via sc_role: root sees all; operator sees operators_only+everyone;
    user sees everyone (root_only/operators_only hidden); owner_only is always
    LISTED (resource-scoped, enforced per-resource at run). Role resolves
    through sc_role when authlib is loaded, otherwise falls back to SC_UID0
    root/user and ignores inherited SC_ROLE values. authgate Part E proves the
    role×class VISIBILITY matrix across both grep and indexed branches (88/88;
    includes explicit inherited-SC_ROLE spoof-denied cells). Strict shellcheck
    clean; harness + datastore green.
  - **WP-E.2.b-1b GAP — `sc help` NOT yet filtered**: help_commands runs at the
    early help-breakout (init.sh:185) BEFORE load_libs (196), so sc_role/get
    are unavailable there; it still shows ALL commands to everyone
    (documented-but-forbidden). AUDIT NOTE: the simple proposed move to AFTER
    load_libs but BEFORE init hooks is NOT sufficient: datastore pre-init has
    only defaulted SC_DATASTORE_DIR to the RO path, while init_datastore has not
    selected/exported the final RW/RO store. A non-root operator's sc_role/get
    lookup would therefore read the wrong/stale store or fail safe to user.
    Filtering sc help needs either a non-mutating datastore role-read bootstrap
    or an init split that selects the datastore without running migration, then
    help breakout before mutating init work. FLAGGED before touching init.sh.
  - **WP-E.2.b-2 — classification (user-approved) IN PROGRESS**. Agreed
    classes/decisions: installers→owner_only (deferred, need container-arg
    check), VE-side usersonve→keep current (own role space), update-ve→
    owner_only, add-vnc-user→owner_only, add-publickey→everyone, reseller_only
    commands STAY reseller_only (re-tag would lock out still-active a-z
    resellers → WP-F). Slice 1 DONE (enforcement): add-ve/add-network-ve/
    add-codepad authorize-stub→operators_only (tightens provisioning to root+
    operator); add-vnc-user gained owner_only (closes its no-authz gap,
    check-before the datastore write). selftest/classification.test.sh =
    line-anchored manifest (14/14) proving the tags are APPLIED; guards proven
    behaviourally by authgate Parts D/E. Strict shellcheck clean.
    - **AUDIT FIX — visibility marker parser ✅**: the command index parser and
      bash fallback now detect LINE-ANCHORED guard CALLS across the WHOLE file,
      not HEAD-20 loose substrings. This closes both exposed mismatches:
      add-ve/add-codepad/add-network-ve operators_only calls beyond line 20 are
      now hidden from ordinary users, and regenerate's commented `##root_only`
      no longer hides a runnable command. commandindex has explicit regression
      checks for late operators_only + commented root_only; authgate Part E
      proves both grep and indexed visibility branches.
    - **Remaining tags**: root_only adds (customize, fix-owner, fix-sshd,
      fix-saslauthd, exec-all, regenerate real guard),
      update-ve→owner_only, testsaslauthd root_only→operators_only (widening),
      installer owner_only decision; then extend the manifest to all 38.
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
