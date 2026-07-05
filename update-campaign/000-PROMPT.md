SRVCTL 4 REWRITE CAMPAIGN — PLAN FIRST, THEN SEQUENTIAL EXECUTION

STATUS (2026-07-05, end of session 1): DISCOVERY + AUTHORIZED POLISH PASS
COMPLETE. Branch v4 (from e179f53), 38 functionality-preserving polish
commits (core + all 37 modules), not pushed. Discovery fact sheets + 301
findings filed; Phase B plan DRAFTs 010–019 written. AWAITING human review
of the plan set (Stage gate) before any Stage 2 code. See 000-INDEX.md
(session log + NEXT) and 020-session1-report.md. This prompt remains the
governing contract; re-read it at the start of each session and update this
STATUS line (and 000-INDEX.md) at the end of every session.

AUDIT-THE-AUDIT ADDENDUM (2026-07-05, Codex, current HEAD ab4325b)
Read all update-campaign files and re-checked the current v4 branch source.
This addendum is a planning/session-start guard only: do not treat it as
source-code authorization. Before Stage 2 starts, fold these items into the
relevant plan/work-package docs or explicitly close them.

Missed or under-consolidated runtime findings:
1. srvctl networkd failure paths can exit success. In
   modules/srvctl/libs/networkdlib.sh, failed systemd-networkd start,
   failed systemd-resolved start, and failed post-migration ping each do
   `err ...; exit` with no status. Because `err` returns success, an
   update-install path can terminate with exit 0 after a network migration
   failure. This is already marked inline as FIXME(v4), but it is not
   consolidated in 003-discovery-findings.md or the srvctl fact sheet's
   bug list. Make it a Stage 2 work item, because containers'
   pre-update-install-host hook calls this path on host update-install.
2. datastore has the same unsafe `if $SC_USE_GLUSTER` pattern already filed
   for static, but it was missed for datastore. See
   modules/datastore/hooks/init.sh and
   modules/datastore/hooks/update-install-host.sh. In bash, an empty command
   variable in `if $var; then` evaluates through an empty command and enters
   the then branch. If G4 removes the gluster module or its config before
   datastore/static hooks are rewritten, these hooks can take the gluster
   branch, call undefined gluster helpers, or select the read-only gluster
   datastore path during init/update-install.
3. The v4 hook contract drafts are currently too loose and partly wrong
   relative to v3. Current startup runs pre-init-$CMD, pre-init, load_libs,
   init, post-init, post-init-$CMD from init.sh; plain command dispatch does
   not wrap every command in pre-$CMD/$CMD/post-$CMD. commonlib.sh run_hooks
   provides pre-X/X/post-X only at explicit call sites. Do not implement a
   generic command wrapper unless a plan intentionally changes this contract
   and audits every hook user.
4. Hook execution depends on sourced caller scope, not just hook name/order.
   Examples include mkrootfs_fedora hooks in codepad, firewalld, and postfix
   reading caller-local variables such as rootfs_name/rootfs_base. Current
   run_hooks also ignores extra arguments passed by callers such as
   addcontainerlib.sh. A v4 .mjs dispatcher that runs hooks in isolated child
   processes or assumes argv parameters will break existing behavior unless
   the affected hooks are ported with explicit data contracts.
5. The inline FIXME(v4) inventory is not fully reconciled with the campaign
   ledger. A current non-vendored scan finds more markers than the session-1
   summary recorded, and the networkd example proves at least one marker is
   not represented in 003-discovery-findings.md. Before creating 100-series
   work packages, generate or reconcile a complete FIXME(v4) inventory.

Campaign ledger drift to correct before Stage 2:
- 000-COVERAGE.md still shows postfix polish unchecked, while git history,
  000-INDEX.md, and 020-session1-report.md say all 37 modules were polished.
- 000-INDEX.md still says the checkout is master / 1 commit ahead of origin
  in one place, while the actual branch is v4 and the same file later says
  v4.
- 000-INDEX.md lists core.md and modules/*.md as pending in the first table
  and written in the session-1 additions table.
- Module fact sheets are baseline-grounded, often titled with commit 988c38c.
  Some line references and bug lists predate the polish commits. Treat them
  as discovery context, not current HEAD truth, unless re-verified.

This is a multi-session campaign in two macro-stages:
  STAGE 1 — PLANNING: produce numbered .md plan documents and work packages
            in this folder. NO source code is modified in Stage 1.
  STAGE 2 — EXECUTION: work packages are executed sequentially, one per
            session, by multiple agents/LLMs, each gated by verification and
            by the production-safety rules below.
The stage gate between 1 and 2 is a HUMAN review of the plan set. Do not
begin Stage 2 without an explicit human "plans approved" note in 000-INDEX.md.

CONTEXT
- srvctl v3 (currently 3.2.5.9) is a container farm manager for microsite
  hosting on Fedora servers: systemd-nspawn containers, bash-heavy with
  legacy light JS. Live checkout: /srv/srvctl (deployed on ~5 production
  servers). Working checkout for this campaign: /srv/srvctl-project.
- Boilerplate v4 is the reference framework: /srv/v4-devel-project.
  Its documentation/framework-philosophy.md and CLAUDE.md are normative for
  all new .mjs code written in this campaign (module collections, fun/ run/
  store/ hooks/ config/ conventions, per-module node_modules, no unnecessary
  external packages).
- srvctl v3's CLAUDE.md describes the current architecture (module structure,
  hook order, SC_ variables, command doc format). Read it before auditing v3.
- A prior campaign of this style (identification-only audit) lives at
  /srv/v4-devel-project/documentation/audits/issue-identification-2026-07-01/
  — its ledger discipline (000-INDEX / 000-COVERAGE / numbered issues with
  model suffixes) is the template for this one.

GOALS (normative — every plan document must trace back to one or more)
G1  PERFORMANCE / LANGUAGE SPLIT. srvctl3 is slow. Rewrite to "light bash":
    bash remains only as thin entry/dispatch and where the OS demands it;
    .mjs files do the heavy lifting (config parsing, datastore access,
    templating, orchestration logic). Measure: cold `sc` dispatch and common
    commands must get dramatically faster; record baseline timings in Phase A.
G2  BOILERPLATE INTERFACE. The d250.hu container runs a boilerplate 4
    instance with the d250 app by default. The v3 datastore concept moves to
    a boilerplate-based `srvctl-modules/datastore` module (a new module
    collection in the boilerplate ecosystem), so farm data is managed from
    there. Define the host<->boilerplate API (transport, auth, failure modes)
    as an explicit plan document.
G3  LLM-DRIVEN QUALITY. v3 was hand-written and carries bugs and
    architectural debt. The campaign explicitly uses LLM agents to find and
    fix these during the rewrite — every module port includes a mini-audit of
    the v3 behavior it replaces (bugs found are filed, not silently fixed,
    so migration risk is visible).
G4  DROP GLUSTER. The gluster module is removed. Plan must state what (if
    anything) replaces shared storage on hosts that used it, and the removal
    steps on live servers.
G5  GUI → COCKPIT (+ optional boilerplate admin UI). The v3 gui module is
    retired. Cockpit is the Fedora-supported path: plan srvctl cockpit
    modules/extensions for host and in-container management for our users.
    A boilerplate-based admin UI may complement it; cockpit is the default.
G6  DEPRECATE RESELLERS. No pre-created users a..z. Plan the user model
    without the reseller layer and the migration for existing servers that
    still carry those accounts.
G7  WILDCARD CERTIFICATES. letsencrypt module moves to wildcard certs via
    DNS-01. This couples to the named/dns modules — the plan must cover the
    challenge automation, renewal, and distribution of certs to containers
    and proxies.
G8  OPENVPN → ZEROTIER. The OpenVPN 10.15.x.y mesh is deprecated. Zerotier
    replaces cluster-host connectivity. Note: work already started —
    modules/usersonve/commands/add-zerotier.sh exists (currently modified,
    uncommitted, in /srv/srvctl). Plan must cover HOSTNET addressing impact
    and a mesh migration that never leaves a host unreachable.
G9  MAIL PROXY. perdition is deprecated, but POP3S/IMAP4S still need a
    reverse proxy to per-container mail. Plan document must evaluate
    candidates (nginx mail proxy, haproxy, dovecot proxy, sslh) and pick one,
    with SNI-based routing as the presumed mechanism — decision filed
    -for-human if trade-offs are not clear-cut.
G10 SIMPLIFY. Less code, fewer special cases. Every ported module states
    what it deleted. Cross-module duplication found during porting is filed
    as a cross-cutting issue with the full file:line list.
G11 PERMISSIONS. Proper user permission management replaces v3's ad-hoc
    authorize/sudomize checks: one plan document defines roles, the
    permission model, and where it is enforced (bash shim, .mjs core,
    datastore, cockpit).
G12 KEEP THE MODULAR STRUCTURE. The module concept (module-condition,
    commands, hooks, libs, conf) works and survives into v4, adapted to the
    bash-shim + .mjs split. Plan the v4 module contract explicitly.
G13 PRODUCTION CONTINUITY. ~5 production servers stay online. Development is
    tested on live servers, so every execution work package carries explicit
    migration steps, a verification step, and a rollback step. v3 and v4
    must be able to coexist on a host during transition (side-by-side
    install, not in-place mutation) — the coexistence mechanism is itself a
    plan document.

CAMPAIGN PHASES
STAGE 1 (planning; writes only inside this folder):
  PHASE A — DISCOVERY (expect 2-4 sessions)
    Step 0 (session one):
      - Read /srv/srvctl/CLAUDE.md, init.sh, commonlib.sh, srvctl.sh.
      - Inventory all 37 modules; create 000-COVERAGE.md listing every
        module with disposition column: keep-port | rewrite | absorb |
        deprecate | undecided. Seed the known verdicts: gluster=deprecate
        (G4), openvpn=deprecate (G8), perdition=deprecate (G9),
        gui=deprecate (G5), and the reseller mechanics inside the user
        modules=deprecate (G6).
      - Record baseline performance numbers (time `sc` dispatch, time 3-5
        common commands) into 001-baseline.md — these are the G1 yardstick.
      - Create 000-INDEX.md (ledger, see INDEX below).
    Later Phase A sessions: per-module fact sheets — what each remaining
    module actually does, its hooks, its state, its host/container touch
    points, and known bugs/smells (mini-audit, G3). Batch several small
    modules per session; big ones (ve, usersonve, containers, datastore)
    get their own session.
  PHASE B — ARCHITECTURE PLANS (one .md per topic, numbered 0NN):
    Required plan documents (at minimum):
      - v4 runtime architecture: the bash shim, the .mjs core, process
        model, where node runs (host and/or container), startup path (G1)
      - v4 module contract (G12) — the successor of module-condition/
        commands/hooks/libs/conf under the new split
      - datastore migration to boilerplate srvctl-modules/datastore, and
        the host<->boilerplate API (G2)
      - permission model (G11)
      - networking: zerotier mesh design + HOSTNET impact (G8)
      - certificates: wildcard DNS-01 design (G7)
      - mail proxy selection and design (G9)
      - cockpit integration design (G5)
      - v3/v4 coexistence + per-server migration playbook skeleton (G13)
      - repo/branch strategy for the v4 code itself (-for-human decision:
        new repo vs. v4 branch vs. subdirectory)
    Each plan document ends with a list of the work packages it implies.
  PHASE C — WORK PACKAGES: convert plans into numbered execution issues
    (100+ series, see FILING). Order them into a dependency-respecting
    sequence in 000-INDEX.md. Sizing rule: one work package = one session.
  GATE — human review, "plans approved" recorded in 000-INDEX.md.
STAGE 2 (execution):
  PHASE D — BUILD: execute work packages strictly in the sequenced order,
    one per session. Each session: implement, verify, update ledger, update
    the changelog of the code repo. Code style: boilerplate philosophy for
    .mjs, srvctl conventions (SC_ vars, msg/ntc/prg/err, ShellCheck-clean)
    for the remaining bash.
  PHASE E — ROLLOUT: per-server migration, one server at a time, starting
    with the least critical host. Each server gets a dated migration report
    filed in this folder. Only after a server has run v4 cleanly does the
    next one start.

SESSION START PROTOCOL (every session)
1. Read this file, then 000-INDEX.md and 000-COVERAGE.md. If 000-INDEX.md
   is absent, this is session one → run PHASE A STEP 0.
2. Record the current git commit hash of /srv/srvctl-project (and, once it
   exists, of the v4 code repo) in the ledger. If it differs from the
   ledger's last hash, note the drift — line references in filed documents
   may have rotted; do not silently trust them.
3. Resume at whatever 000-INDEX.md names as next. Resumption is the NORMAL
   mode: at session end the ledger must reflect actual state and name the
   next unit of work.
4. In Stage 2, additionally read the work package being executed and every
   plan document it cites, before touching code.

PRODUCTION SAFETY RULES (Stage 2 and any live probing in Stage 1)
- Live servers are production. Read-only probes are always allowed; any
  state-changing test needs the work package to name it and needs a rollback
  line next to it.
- Never modify /srv/srvctl (the live v3 checkout) as part of development;
  v4 work happens in its own location per the repo-strategy plan doc.
- No irreversible steps (data deletion, module removal, cert cutover, mesh
  cutover) without a verified backup and a tested rollback. Deprecations
  (G4, G6, G8, G9) are executed as: install replacement → verify → disable
  old → observe → remove old, never in one step.
- Anything that would take user-facing services offline for more than a
  reload is filed -for-human and scheduled, not improvised.

FILING (all files live in this folder)
- 000-*: ledger files only (000-PROMPT.md, 000-INDEX.md, 000-COVERAGE.md).
- 001–099: plan documents and fact sheets (Stage 1).
- 100+: execution work packages (Phase C output).
- Naming: NNN-short-slug-for-MODEL.md. MODEL suffix by difficulty:
  -for-fable (architectural / hardest), -for-opus (moderate), -for-codex or
  -for-glm (mechanical), -for-human (judgment or product decision required).
  Plan documents that are pure description need no suffix. IDs are stable
  and never renumbered; ordering lives in the index, not the filename.
- Required sections for a WORK PACKAGE: Title; Goal trace (G-numbers);
  Depends on / blocks (IDs); Affected modules/files; Description; Steps;
  Verification method; Migration steps (per-server, if it touches live
  state); Rollback; Status (pending / in-progress / done / blocked).
- Required sections for an ISSUE (bug found during audit or porting, G3):
  Title; Severity (blocker / high / medium / low); Category; Affected files
  (path:line + commit hash); Description; Concrete harm; Proposed fix;
  whether v4 must preserve or fix the behavior (-for-human if unclear).
- BAR FOR FILING issues: concrete harm stated, no style-only findings
  unless cross-cutting. Cross-cutting patterns: ONE file, occurrence count,
  full file:line list.

INDEX
Maintain 000-INDEX.md across sessions: session log (date, git hashes, what
was done); table of all documents (ID, title, type plan/package/issue,
status, model, goal trace); the approved execution sequence (Phase C
output); the stage gate record; per-server rollout status (Phase E); a
short executive summary; and always: NEXT = the next unit of work.

OPEN DECISIONS (seed list — file each as it gets resolved)
- Repo/branch strategy for v4 code (-for-human).
- Node.js runtime distribution: host package vs. bundled, and minimum
  version.
- Mail proxy candidate (G9) if evaluation is not clear-cut (-for-human).
- Whether the boilerplate admin UI ships in v4.0 or only cockpit (G5)
  (-for-human).
- Zerotier: self-hosted controller vs. hosted, network ID management (G8).
- What, if anything, replaces gluster's shared-storage role (G4).
