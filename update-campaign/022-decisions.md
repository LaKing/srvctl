# 022 — Decision brief (Stage 1→2 gate)

Every open decision from 000-PROMPT and the plan drafts (010–019), in one
place. Fill in the `Decision:` line under each. My recommendation is the
first option and marked **REC**. Nothing here changes source code — these
answers turn the DRAFT plans into an approved plan set and an ordered
100-series work backlog.

Three kinds of item, tagged:
- **[CHOICE]** — a call only you can make; I have a recommendation.
- **[FACT]** — something true about the current fleet that I can't see from
  the repo; you know it or it needs a quick check on a server.
- **[CONFIRM]** — I'm fairly sure; just need your yes.

Two tiers:
- **TIER 1 — decide now**: these gate the overall Stage-2 architecture and
  the "plans approved" note. ~10 items, most are quick.
- **TIER 2 — decide when the work package starts**: feature specifics
  (zerotier, certs, mail, cockpit, rollout). Recorded here so nothing is
  lost, but they don't block approval.

---

## TIER 1 — decide now (gates Stage 2)

### D1 [CHOICE] Where does the v4 code live? (010 Q3, G13)
Blocks: everything — the repo/install shape.
- **REC**: keep developing on branch `v4` in this repo (history continuity,
  what we have now); install v4 side-by-side at `/usr/local/share/srvctl4`
  with a `/bin/sc4` symlink so v3 and v4 coexist on a host (per 013). v3 is
  never mutated; rollback = repoint symlinks.
- Alt: brand-new repo (clean history, but loses the polish commits' context
  and the fact-sheet cross-refs).
Decision:

### D2 [CHOICE] Node runtime + minimum version (010 Q1)
Blocks: runtime.mjs, the whole .mjs core.
- **REC**: use distro `nodejs` (v3 already dnf-installs it); pin a floor of
  **Node ≥ 20** (LTS). This host has v22; boilerplate presumably wants
  modern node too, so ≥20 is safe and avoids bundling a runtime.
- Alt: pin ≥22, or bundle a fixed node (heavier, but removes distro drift).
Decision:

### D3 [CHOICE] Command execution model (010 Q2)
Blocks: the dispatcher design (G1 performance).
- **REC**: run the dispatched command **in-process** in the one node
  process. srvctl is a short-lived CLI (one command per invocation, then
  exit) — there's no long-running daemon to protect, so in-process is the
  fast path and the G1 win. Legacy `.sh` commands still run via one bash
  child.
- Alt: fresh node child per command (more isolation, slower — only worth it
  if we later add a persistent daemon).
Decision:

### D4 [CHOICE] mjs dependency layout (011 Q2)
Blocks: module contract.
- **REC**: a **single core `package.json`** / one `node_modules` for the
  whole srvctl mjs core. srvctl is small; boilerplate's per-module
  node_modules solves a scale problem srvctl doesn't have. Add a per-module
  dep only if one module genuinely needs it.
- Alt: per-module node_modules (boilerplate-style).
Decision:

### D5 [CONFIRM] User custom commands: mjs lane or bash-only? (011 Q1)
Blocks: module contract; couples to G11.
- **REC**: **bash-only** for `~/srvctl-includes` in v4.0. Running
  in-process node code from user home dirs is a privilege question that
  needs the G11 permission answer first. Revisit after permissions land.
Decision:

### D6 [CHOICE] update-install side effects: keep or split? (013)
Blocks: the update-install rewrite; this is a behavior change needing your
sign-off.
- **REC**: **split** the heavy implicit side effects (`dnf update` of the
  whole OS, `SELINUX=disabled`) out of `update-install` into explicit
  opt-in subcommands. Today a routine update silently upgrades the OS and
  disables SELinux — surprising and risky on production. Splitting is a
  behavior change, hence your call.
- Alt: keep v3 behavior (no surprises for existing muscle memory, but keeps
  the footguns).
Decision:

### D7 [CONFIRM] Retire the v3 GUI daemon module (018 Q1, G5)
Blocks: nothing risky — the module's install hook is already `if false`
(dormant all through v3), so no running host depends on it via srvctl.
- **REC**: **yes, retire it**; keep only `make_commands_spec` (the JSON
  command metadata, reused by cockpit). Any running srvctl-gui is
  srvctl2-era leftover, handled per-server in rollout.
Decision:

### D8 [CONFIRM] Gluster: confirm nothing to preserve (019, G4)
Blocks: the G4 removal package (which already has the hook-ordering
constraint baked in).
- **REC**: gluster is hard-disabled at baseline; **nothing replaces its
  shared-storage role** — datastore replication moves to G2, static is
  single-host + backups. Need your confirm that no host was manually
  re-enabled for gluster outside srvctl (the per-server inventory step
  double-checks; non-empty bricks → stop and ask).
Decision:

### D9 [FACT] Are there non-root human admins on the ~5 servers? (012 Q1)
Blocks: the G11 permission model (roles).
- Context: v3's `authorize` is a stub; effectively it's root + end-users
  today. If there are human operators who are neither root nor end-users, the
  model needs an `operator` role.
Decision:

### D10 [CHOICE] Can end users run `sc` on the HOST in v4? (012 Q2)
Blocks: G11 model + cockpit scope (G5).
- **REC**: **no** — end users manage their containers via cockpit /
  in-container only; host `sc` is root/operator-only. Cleanest security
  boundary and it lets G11 stay simple.
- Alt: keep host `sc` for users with per-resource ownership checks (more
  code, bigger attack surface).
Decision:

### D11 [FACT] Is per-user ownership recorded authoritatively today? (012 Q3)
Blocks: G11 enforcement + migration.
- Context: fact sheets show container→user in the datastore
  (`containers.json`, `users.json`, `default-users.json`). Confirm that's
  the source of truth (so v4 enforces from it), or note what must be
  reconstructed during migration.
Decision:

---

## TIER 2 — decide when the work package starts (not blocking approval)

### Datastore → boilerplate (G2, doc 014)
- **D12 [CHOICE] Host↔boilerplate transport/auth.** REC: v4.0 stays
  **file-sync compatible** (keep the 3 JSON files, in-process mjs reads,
  rsync as today) so no new failure modes; add an authenticated HTTP API
  (over the zerotier mesh) for the admin UI as a *later* package.
  Decision:
- **D13 [FACT] Reuse d250 app models or build fresh?** Needs a look at
  `/srv/v4-devel-project` d250 app. REC: fresh `srvctl-modules/datastore` on
  boilerplate conventions, reusing d250 models only where they already fit.
  Decision:
- **D14 [CHOICE] Topology: one cluster instance vs per-host.** REC: one
  boilerplate instance (d250.hu) as source-of-truth + per-host read cache
  (works during bootstrap / when the container is down).
  Decision:

### ZeroTier mesh (G8, doc 015)
- **D15 [CHOICE] Controller: self-hosted vs my.zerotier.com.** REC:
  **self-hosted** (ztncui/zerotier controller on a cluster host) — keeps the
  farm self-contained, matches the srvctl ethos.
  Decision:
- **D16 [CHOICE] Addressing: reuse 10.15.x.y inside ZeroTier or fresh
  range.** REC: **reuse 10.15.x.y** — avoids config churn across nfs, ssh
  known-hosts, datastore sync, named that all reference those addresses.
  Decision:
- **D17 [FACT] Scope of your add-zerotier.sh WIP.** Is ZeroTier also the
  user/container access path (the usernet successor), or only the host mesh?
  One network or two? You know the intent behind the WIP.
  Decision:

### Wildcard certificates (G7, doc 016)
- **D18 [FACT] Domain inventory.** Which hosted domains are subdomain-based
  (wildcard-eligible) vs customer-owned? Needs a per-server look; feeds the
  issuance plan.
  Decision:
- **D19 [CHOICE] SAN strategy.** REC: one wildcard per hosting domain
  (`*.domain` + `domain`); per-customer-domain certs kept separately.
  Decision:
- **D20 [CHOICE] Renewal authority location.** REC: the DNS **master** per
  domain runs renewal (it owns DNS-01) and distributes bundles cluster-wide.
  Decision:

### Mail proxy (G9, doc 017)
- **D21 [CHOICE] Proxy pick.** REC: **nginx mail proxy** (auth_http routes
  by `user@domain`, TLS with the wildcard cert, tiny config from
  containers.json). Alt: haproxy SNI passthrough (fewer new components, but
  no login-based routing).
  Decision:
- **D22 [FACT] Plaintext IMAP4 (143/STARTTLS) still needed, or S-ports
  only?** You know the client base.
  Decision:
- **D23 [FACT] Do all mail containers run dovecot with user@domain logins?
  Any POP3 (110) legacy clients?** Confirms the routing assumption perdition
  made.
  Decision:

### Cockpit (G5, doc 018)
- **D24 [CHOICE] Exposure.** REC: bind cockpit to the **mesh/VPN only**
  (or public 9090 behind strong auth); authenticate as Unix users via PAM.
  Decision:
- **D25 [CHOICE] Build priority.** REC: **host-admin package first** (needs
  no full G11), user-facing in-container management after G11 lands.
  Decision:

### Rollout (G13, doc 013)
- **D26 [FACT/CHOICE] Server order + soak time.** REC: least-critical host
  first, then one at a time with a multi-day soak each. You pick the order.
  Decision:
- **D27 [CHOICE] When to delete v3 from a cut-over server.** REC: only after
  **all** servers run v4 through a full backup cycle; keep `/bin/sc3` for
  instant rollback until then.
  Decision:

---

## After you answer

Answer TIER 1 (and any TIER 2 you already know) + write "plans approved" in
000-INDEX.md, and I will:
1. Fold the answers into the relevant plan docs (drop the DRAFT tag on the
   ones fully resolved).
2. Generate the **100-series work packages** in dependency order, each with
   Goal trace, steps, verification, per-server migration + rollback, drawing
   FIXME items from 021 and honoring the Stage-2 preconditions
   (HEAD re-verify, hook contract, G4 ordering).
3. Start Phase D with the first package (per D1–D3 that's the v4 runtime
   skeleton: bash shim + mjs dispatcher reading the existing datastore).

TIER-1 items still marked [FACT] that you leave blank become the first
questions in their work package, not blockers to approval.
