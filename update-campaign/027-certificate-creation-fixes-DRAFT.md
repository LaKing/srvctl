# 027 — Container certificate creation fixes (WP-CERT) — DRAFT for review

Status: DRAFT 2026-09-25, revision 8. Research + eight external audit rounds
folded in; not approved. Nothing implemented beyond the uncommitted work under
"Current tree". Rounds 7 and 8 were limited to service activation and
its tests, and are applied; approval is the remaining step.
Branches: hotfix on `master` (production), port/extension on
`wildcard-certificates` (unmerged WP-H branch, see 016).

Revision 2 changes (audit round 2): staging rejected in both eligibility checks
and never published to production destinations; master prune driven by the
retained set; Phase 0 is a dedicated read-only command with a named rollout
setting; master gets the run lock; removal and retention share one name
expansion; container activation is fingerprint-based and retried; WP-CERT-3 is
backported; shared helpers live in a new `http01lib.js` on both branches;
explicit test lists.

Revision 3 changes (audit round 3): staging is honoured only by a dedicated
http-01 trial command and refused by every `regenerate` path (host, DNS-01,
fan-out, haproxy); certificate classification is separated from renewal
timing; throttle attempts are reserved before certbot runs; activation
fingerprints cover the whole deployed chain and key; per-hotfix acceptance
criteria, with the gate flipped only after hotfixes A–C; wording fixes on the
`legacy` default and the first-run reload.

Revision 4 changes (audit round 4): the staging config flag is retired and
refused by a letsencrypt `pre-init` hook before any hook that changes files,
with exit 45, and `letsencrypt.js` keeps its own refusal as a second guard;
staging certs are never served (D-CERT-7), covering per-domain selection,
admin wildcards, fan-out, service certs and master's copy path; the hotfix-A
rebuild claim is qualified and acceptance A separates local repairs from ACME
work; exact-boundary tests for `daysLeft` 7 and 3. Choices confirmed by the
reviewer: DNS-01 staging support removed; 7-day/3-day/6h as initial policy.

Revision 5 changes (audit round 5): the staging guard moves from a
letsencrypt hook into core `init.sh`. It runs before `pre-init-$CMD` and
every module, works with the module disabled, applies to every command, and
promises unchanged certificate destinations rather than a mutation-free run.
D-CERT-7 now defines, for each listener (haproxy, service TLS, container
httpd), what is selected, the non-staging fallback, and how the change is
activated, including an empty haproxy set, a failed config check or reload,
and service certs that are only refreshed at update-install. Real-listener
tests are added. master's haproxy and service-cert staging rejection moves
into hotfix A; the container httpd claim waits for hotfix C.

Revision 6 changes (audit round 6, local corrections): exit 45 is described as
an unused *production CLI* code. D-CERT-7 now promises rejection from the
desired set and removal from live service after successful activation; old
certs keep being served while activation fails. The haproxy fallback is
excluded when judging emptiness and is pruned once ordinary certs return. A
new verified fallback generator `sc_fallback_cert` works in a dedicated
directory and checks its output is not staging. Service TLS uses a fixed
service table (no discovery file) and fingerprint-based activation with
retry. Listener failure tests expect the old cert to keep being served until
the retry. Choices confirmed by the reviewer: exit 45, keeping haproxy
running after a failure, the fallback only when the set is empty.

Revision 7 changes (audit round 7, service activation only):
- postfix and perdition are activated inside their existing hooks, which
  already restart on every `regenerate` on master too (verified), so no
  second restart is added; master's hooks gain the certificate refresh.
- `restart_perdition` returns an aggregate status over all three units.
- Fingerprints are recorded only after a fully successful restart.
- The new `service_certs_activate` step covers gui only, and acts only when
  gui is active or has a `pending` retry from its own failed restart.
- Tests distinguish a restart rejected before the stop (old cert still
  served) from a startup failure after it (service down), with a retry in
  both cases.
- The first-run note is corrected: only gui gets an extra restart.

Revision 8 changes (audit round 8, activation contract):
- `pending` is an unresolved activation attempt (after a rejected restart, a
  failed startup or a crash). It authorises automatic recovery until it is
  cancelled with the new `sc cert-pending-cancel SERVICE`; a plain operator
  stop does not cancel it.
- Recording success requires every restart command to return 0 **and** every
  unit to be active; the postfix and perdition restart helpers change to
  capture command status.
- The gui certificate is replaced before the eligibility check.
- Tests cover a failed restart command with the unit still active (postfix,
  and an early perdition unit), a crash after `pending`, and cancellation
  before the next `regenerate`.

## Storage map (verified at HEAD of wildcard-certificates)

| Location | Content | Writer |
|---|---|---|
| `/srv/<C>/cert/` | per-container self-signed set: `<C>.key/.crt/.pem`, `cert.pem`, scratch `config.txt` (holds the passphrase), `random.txt`, `<C>.key.org`, `<C>.csr` | `add_ve_certificate` → `create_selfsigned_domain_certificate` |
| `/srv/<C>/rootfs/etc/pki/tls/{certs,private}/localhost.*` | container httpd cert; self-signed at creation, then LE or managed wildcard | `add_ve_certificate`, `letsencrypt_deploy`, `acmerun.deployRootfs` (branch) |
| `$SC_DATASTORE_DIR/cert/<domain>.pem` | key + fullchain per domain; self-signed placeholder → LE, or admin-wildcard copy | `add_ve` (hardcoded path), `letsencrypt.js`, `wildcardcertlib.sh`, `acmerun.js` host path |
| `$SC_DATASTORE_DIR/cert/wildcard/<base>.pem` | managed DNS-01 wildcards (branch) | `acmerun.js` |
| `/etc/srvctl/cert/<dom>/*.pem` | admin-installed certs | admin |
| `/etc/letsencrypt/live/<lineage>/` | certbot lineages | certbot |
| `/var/haproxy/*.pem` | what haproxy serves; branch: rebuilt + pruned by `sync_haproxy_certificates`; master: `cp -u`, never pruned | haproxy regenerate |
| `/etc/srvctl/CA/` | private CA (VPN/gluster), not web | `calib.sh` |

Container flow: `add_ve` creates a 10-year self-signed cert and copies it into
`datastore/cert/<C>.pem` as a placeholder; the next `regenerate` is meant to
recognise the placeholder and issue via http-01.

## Findings

### F1 (critical, master + branch) — placeholder never recognised, LE never issued
`letsencrypt.js` `check_datastore_cert` matched `"emailAddress = webmaster@"`.
OpenSSL 3.5.7 prints `subject=CN=x, emailAddress=webmaster@x` (no spaces), so
the placeholder passes as a valid real cert and the domain is skipped for its
10-year life. Reproduced in a scratch run. master: `letsencrypt.js:155`.

### F2 (high) — removed containers keep being served
`remove-ve` / `destroy-ve` never removed `datastore/cert` files. Branch
`sync_haproxy_certificates` serves every valid pem in that dir; master's
`cp -u` into `/var/haproxy` never removes anything. Historical orphans exist in
both the datastore and `/var/haproxy`, on every serving host.

### F3 (low) — junk placeholder for non-Fedora images
`addcontainerlib.sh:71-76` copies even when `add_ve_certificate` created
nothing; the redirect creates a file holding only `run`'s ANSI banner.

### F4 (low) — ANSI banner first line in every placeholder
`run cat X > Y` writes the command echo into Y (same bug on `resolved.conf`).

### F5 (latent) — placeholder path hardcoded
`add_ve` writes `/var/srvctl3/datastore/cert`, readers use
`$SC_DATASTORE_DIR/cert`; differs only after a failed gluster mount (RO mode).

### F6 (medium) — private keys world-readable
Generated key/pem files and LE deploy writes use the default umask (0644);
`datastore/cert` is protected only by the parent-dir mode `set_permissions`
applies at update-install. `writeFileSync(..., {mode})` does not change an
existing file's mode (verified: 644 stays 644).

### F7 (high) — staging: flag ignored by http-01, and staging certs block production
`SC_LETSENCRYPT_STAGING` only reaches `acmerun.js:77`. Separately, a staging
certificate — in `datastore/cert` or in a production lineage — passes both
eligibility checks (`check_datastore_cert`, lineage `check_checkend`), which
test expiry only, so the domain is skipped and production issuance never
happens. Separate certbot dirs do not isolate the shared datastore, the
container rootfs or haproxy. On the branch the whole `regenerate` path is
exposed, not only container http-01: `acmerun.hostPath` passes `--test-cert`
and then writes the staging host cert into `datastore/cert/<fqdn>.pem`
(`acmerun.js:833-841`, its "existing" check is expiry-only too); DNS-01
`publish` puts staging wildcards into the bundles dir that serving hosts pull,
and `evaluateNames` installs them and calls `deployRootfs`; the same
`regenerate` then runs wildcard fan-out and the haproxy sync.
`documentation.md:1853` already warns "never on a production primary: nothing
checks the issuer", and `016-wildcard-trial-primary.sh:191` refuses to run
with the flag set.

### F8 (high) — naive per-run cap starves domains
Stable iteration order + no memory across runs: the first N permanently
failing domains consume every run. The http-01 path has no cap today
(`SC_ACME_MAX_ISSUE_PER_RUN` is DNS-01 only, `acmerun.js:78`).

### F9 (high) — certificate names ≠ container names
`container_domains()` adds aliases, altnames, `www.` variants and subdomains;
`acmerun.js:841` writes `cert/<host-fqdn>.pem`; wildcard fan-out writes
`<C>.<company-domain>.pem`. Deletion candidates and retained names must use
one expansion.

### F10 (medium) — issuance ≠ activation, and failures are not retried
master `proxylib.sh:51-56` skips the haproxy reload on hourly runs; neither
branch reloads the container httpd after writing its cert. A reload tied to
"written this run" is lost on failure: the next run sees a valid datastore
cert and never deploys again.

### F11 (medium, master only) — expired DST Root CA X3 appended
master `letsencrypt.js:173-181` appends `/etc/letsencrypt/ca.pem` to every
bundle (the branch fixed this via `bundlelib`).

### F12 (high for WP-4) — replace-by-rename breaks container TLS
Containers run with `PrivateUsers=` (`generators.mjs:151`). A temp+rename write
by host root leaves the file owned by host root → `nobody` inside the
container → an 0600 key is unreadable → httpd fails. `check_container_pki_ownership`
repairs it, but the `containers` regenerate hook (module position 8) runs
before haproxy triggers the LE deploy (position 16). `acmerun.deployRootfs`
already preserves the directory owner, via `atomicWrite` (below).

### F13 (medium, master) — no run lock
master `letsencrypt_main` runs `letsencrypt.js` without the branch's `flock`;
any shared state added by this package would race between overlapping runs.

### Audit notes — old Phase 0 shell loop is invalid
Two failed `openssl` calls both print "", which compare equal → malformed files
and an unmatched glob are reported "SELF-SIGNED". Issuer equality means
self-issued, not self-signed, and self-signed does not mean orphaned.

### Facts that constrain the plan
- master lacks `bundlelib.js`, `acmerun.js`, `acmeplan.js`,
  `certselectlib.sh`, `generators.mjs`/`main.mjs`, the letsencrypt selftests,
  the settings `export` loop and the run lock. master's datastore is
  `lib.js` (`container_domains` at :683) + `main.js`, which has no `domains`
  getter.
- `acmerun.atomicWrite` (`acmerun.js:107-121`) opens the temp file with `"w"`
  (not exclusive), names it `<file>.tmp.<pid>`, and chowns by pathname after
  writing.
- `bypassNames` is filled only inside `evaluateNames`, which also installs
  wildcards, saves handover state and calls `deployRootfs`
  (`acmerun.js:683-715`); `computeGate` alone does not reproduce it.
- `del` aborts the CLI on failure (`datastore/libs/bashlib.sh:117`), so work
  after `del container` only runs when the record is gone.
- Branch `get container "$C" domains` exists (`main.mjs:171`).

## Current tree (uncommitted, wildcard-certificates, not authored in this session)

| Change | Test |
|---|---|
| `check_datastore_cert`: subject/issuer comparison via `-nameopt RFC2253` | `letsencrypt/selftest/datastore-cert.test.mjs` 7/7 pass |
| `remove-ve.sh` / `destroy-ve.sh`: `rm -f $SC_DATASTORE_DIR/cert/$C.pem` after `del` | `containers/selftest/remove-cert.test.sh` passes |
| `check_container_pki_ownership` in containers regenerate | `regenlib.test.sh` |

## Decisions (proposed)

- **D-CERT-1 placeholder policy**: a certificate whose issuer DN equals its
  subject DN is treated as a placeholder and never suppresses issuance. This is
  a deliberate eligibility policy, not a statement about who signed it: equal
  DNs do not prove self-signing (the different-key test shows it), and the
  policy accepts that a legitimately issued cert with equal DNs would be
  re-issued.
- **D-CERT-2 master work in a separate worktree**
  (`git worktree add ../srvctl-hotfix master`); no stashing of branch work.
  `.git/worktrees/` must be writable by codepad (root-owned `.git` caveat).
- **D-CERT-3 build on the current tree**: commit the uncommitted gate fix and
  removal cleanup first, then extend them.
- **D-CERT-4 one shared helper file**: `modules/letsencrypt/http01lib.js`
  (CommonJS, no dependency on `acmerun`/`bundlelib`), byte-identical on master
  and the branch, with the same `selftest/http01lib.test.mjs`. It holds the
  classification (1a), staging detection, throttle state, `secureReplace` and
  container activation. Both `letsencrypt.js` copies call it; this keeps the two
  branches from drifting.
- **D-CERT-5 staging is a separate execution path, never part of
  `regenerate`** (DNS-01 staging removal agreed in audit round 4):
  - The config flag `SC_LETSENCRYPT_STAGING` is retired. Staging exists only
    inside `sc cert-staging-trial DOMAIN...` (WP-CERT-1b), which exports
    the command-scoped `SC_ACME_STAGING_TRIAL=true` to its own node process
    only.
  - **Guard 1, core initialization, before any pre-init dispatch**: a new
    function `sc_refuse_staging_config` in `commonlib.sh`, called from
    `init.sh` on both branches right after `/etc/srvctl/*.conf` and
    `host.conf` are sourced. It runs before `test_srvctl_modules`,
    `pre-init-$CMD` (branch `init.sh:304`, master `:163`), `pre-init` and
    every later hook and dispatch.
    - If `SC_LETSENCRYPT_STAGING` or `SC_ACME_STAGING_TRIAL` is non-empty
      at that point, it prints an error naming the setting and runs `exit 45`
      (an unused production CLI exit code; `regenlib.test.sh:135` uses
      `return 45` only in a test stub) for every command, `cert-staging-trial`
      included. That covers config files and an inherited environment alike.
    - The trial never needs an exemption: it sets `SC_ACME_STAGING_TRIAL`
      itself, later, only in its own node process's environment.
    - The check lives in core, not in a module, so it runs even when the
      letsencrypt module is disabled, and before root-defined custom modules
      or a command-specific `pre-init-$CMD` hook can run.
    - What it promises: **certificate destinations are unchanged**. The
      invocation as a whole is not mutation-free. Earlier `init.sh` steps
      still run: `debug.conf`, the `/bin/sc` symlinks, the host-config
      projection, config sourcing, and anything else that precedes the check
      in that file.
  - **Guard 2, second line**: `letsencrypt.js` (both branches) refuses when
    either variable is set outside `--staging-trial`. It logs an error and
    exits non-zero before any phase: no journal replay, no DNS-01
    issuance/publish/pull/install, no `hostPath`, no http-01, no deploy, no
    activation, no status write.
  - Remove the flag from the settings `export` loop in `letsencryptlib.sh` and
    from `acmerun.js:77` (staging becomes `SC_ACME_STAGING_TRIAL` inside the
    trial only). Update `documentation.md:1853` and the tests that set the
    flag. A DNS-01 staging trial needs its own isolated entry point later (out
    of scope).
  - Staging-issued certs are also rejected for issuance decisions wherever a
    cert is judged: `http01lib.classify` (http-01 and `hostPath` "existing"
    checks) and `acmerun.candidate` (pulled bundles). Serving rejection is
    D-CERT-7.
  - The production path is proven on a pilot host with the production CA,
    not on staging.
- **D-CERT-7 staging certs are rejected from the desired set, and removed from
  live service once activation succeeds.** Neither "never serves staging" nor
  "never an outage" is unconditional: when activation fails, the running
  process keeps serving what it loaded, possibly a staging cert, until a later
  activation succeeds. That window is logged as an error on every run. One
  shell predicate `cert_is_staging PEM` (issuer contains `(STAGING)`), plus
  its `http01lib` twin, is applied per listener. For each listener this
  defines selection, the fallback when no usable replacement exists, and
  activation.
  - **Verified fallback generator** `sc_fallback_cert NAME` (certificates
    module):
    - Generates a self-signed cert for NAME in the dedicated directory
      `/var/srvctl3/acme/fallback/<NAME>/` (0700; files 0600). Nothing else
      writes there, so `create_selfsigned_domain_certificate`'s keep-existing
      early return can only ever reuse its own earlier output.
    - Before any install it checks that the cert parses, is **not staging**,
      has issuer == subject, has a key matching the cert, and has at least 30
      days left. If any check fails, it moves the directory aside
      (`<NAME>.rejected-<ts>`), regenerates once and checks again; a second
      failure logs an error and installs nothing.
    - Used by the haproxy host fallback and the service fallback. The
      container fallback applies the same checks to `/srv/<C>/cert`, and on
      failure moves that directory aside and regenerates it.
  - **haproxy** (`crt /var/haproxy` directory bind, `haproxy.js:388`):
    - Selection: branch `sync_haproxy_certificates` rejects staging in
      per-domain step 2 (next to `cert_valid`), in admin wildcards (inside
      `check_wildcard_pem`) and in managed wildcards (inside
      `wildcard_servable_managed`). master's copy path
      (`load_certificate_folder_files`) skips staging and deletes its
      `/var/haproxy` copy; that part is in hotfix A.
    - Fallback: a domain whose staging cert is dropped is served by a covering
      wildcard if one exists, otherwise by haproxy's default certificate (a
      name mismatch, but not staging).
    - Empty set: emptiness is judged on the desired set **excluding**
      `000-srvctl-fallback.pem` itself. When that set is empty, the sync
      installs `/var/haproxy/000-srvctl-fallback.pem` from
      `sc_fallback_cert <host FQDN>`. Otherwise the fallback is not in the
      desired set, so the prune step removes it as soon as ordinary certs
      return. It cannot stay the default indefinitely, and today's default
      cert order is unchanged whenever real certs exist.
    - Activation:
      - Before reloading, `reload_haproxy` runs `haproxy -c -f` on the
        rendered config (this resolves the FIXME at `systemdlib.sh:42`).
      - Check fails ⇒ no reload and no restart, which would take every site
        down. The old record is kept so the next run retries, and an error is
        logged every run: "staging certificate may still be served by the
        running haproxy".
      - Check passes but the reload fails ⇒ same record and alert.
      - The change-detection reload of WP-CERT-5 is what activates the
        change; it is in hotfix A on master.
  - **Service TLS (postfix, perdition, gui)**, through
    `install_service_hostcertificate`:
    - Known services come from a fixed table in code, so nothing needs
      discovering and existing hosts need no seed file:
      - `/etc/postfix` → `postfix.service`;
      - `/etc/perdition` → `imap4s.service`, `imap4.service`,
        `pop3s.service`;
      - `/etc/srvctl-gui` → `srvctl-gui.service`.
    - Selection: a staging candidate is skipped like a missing one, and so is
      an installed `$path/crt.pem` that is staging.
    - Fallback: the last step becomes `sc_fallback_cert $HOSTNAME`. It no
      longer uses `create_selfsigned_domain_certificate` into
      `/etc/srvctl/cert/$HOSTNAME`, which could keep a rejected cert.
    - Fingerprint = sha256 over `crt.pem`, `key.pem` and `ca-bundle.pem` if
      present, recorded per service in
      `/var/srvctl3/acme/service-activated.json`.
    - **Success rule** (all three services): a fingerprint is recorded only
      when **every** `systemctl restart` for that service returned 0 **and**
      every unit is active afterwards. `is-active` alone is not enough: after
      a rejected restart the old process can still be active. The restart
      helpers change to match:
      - `restart_postfix` and `restart_perdition` capture each
        `systemctl restart` exit status and fail if any restart command
        failed or any unit is not active;
      - `restart_perdition` aggregates over all three units instead of
        returning the last unit's status.
    - **postfix and perdition, both branches**: activation stays inside their
      existing `regenerate` hooks, which already restart unconditionally on
      master and on the branch. There is no second restart anywhere.
      - master: the hooks gain the branch's certificate refresh (the
        guarded `install_service_hostcertificate` call before the restart).
      - Both branches: each hook computes the fingerprint before its restart
        and records it only under the success rule. The unconditional restart
        on every `regenerate` is itself the retry.
      - The perdition hook still returns 0 on failure, so a perdition failure
        keeps not aborting the command (as today). `restart_postfix` returns
        non-zero on failure; its abort behaviour stays as it is (existing
        FIXME).
      - These hooks keep restarting even deliberately stopped services, as
        they do today; changing that is out of scope.
    - **gui, both branches**: a new certificates-module `regenerate` step,
      `service_certs_activate`, is the only activation path. In order:
      1. **Replace the certificate first, whatever the unit state**: if the
         installed `crt.pem` is staging, re-run
         `install_service_hostcertificate /etc/srvctl-gui`. This happens even
         when gui is stopped and will not be restarted.
      2. **Eligibility**: continue only if `srvctl-gui.service` is active or
         its entry is `pending`. The directory existing is never enough to
         start a stopped service.
      3. **Activation**: if the fingerprint differs from the record, write
         `pending: true` (with a timestamp), then `systemctl restart
         srvctl-gui.service`, then apply the success rule.
         - Success: record the fingerprint and clear `pending`.
         - Failure: log an error and keep `pending`.
    - **`pending` means an unresolved activation attempt**, not "the unit was
      left down". It survives a restart rejected before the stop (unit still
      active), a startup failure after the stop (unit down), and a crash
      between writing `pending` and recording the result.
      - It **authorises automatic recovery until it is explicitly
        cancelled**: the next `regenerate` restarts gui even if it is
        inactive, including when an operator stopped it after the attempt.
        A plain `systemctl stop` does not cancel it.
      - To cancel: a new root-only command `sc cert-pending-cancel SERVICE`
        (`modules/certificates/commands/cert-pending-cancel.sh`, guard
        `exit 4`, under the run lock). It clears `pending` for that service
        and leaves the recorded fingerprint as it was, so a gui that is
        started again later is activated by the normal fingerprint
        comparison.
      - `sc cert-inspect` lists pending entries with their age and the
        cancel command. `documentation.md` says the same next to the gui
        service notes.
    - First run after rollout: no record yet ⇒ gui, if active, is restarted
      once by the new step. postfix and perdition get no extra restart: their
      hooks restart on every `regenerate` already, on both branches.
    - Failure semantics: `systemctl restart` stops the unit and then starts
      it.
      - A restart rejected **before the stop** (e.g. a failed job or an
        unusable unit) leaves the old process serving its old certificate,
        possibly staging.
      - A failure **after the stop** (startup fails) leaves the service
        down.
      Both are logged as errors on every run until a later activation
      succeeds, and both are retried: postfix and perdition by the next
      `regenerate`'s restart, gui through `pending`.
  - **Container httpd** (`localhost.crt` / `localhost.key`):
    - Selection: in the WP-CERT-5 activation pass, a container whose
      `localhost.crt` is staging is a rejection.
    - Fallback: the container's own self-signed cert from `/srv/<C>/cert`,
      after the `sc_fallback_cert` checks (regenerated if they fail). It is
      written with `secureReplace`, keeping the shifted owner (WP-CERT-4).
    - Activation: the fingerprint then differs, so the pass reloads httpd and
      retries on failure (WP-CERT-5).
    - Lands with hotfix C (activation). master never had a staging-capable
      path into a rootfs; only a manual copy could put one there.

  A rejected source cert is left on disk (logged); only serving copies are
  replaced. Each rejection, each fallback and each failed activation is logged
  as an error, and `sc cert-inspect` lists them per listener.
- **D-CERT-6 rollout setting**: `SC_ACME_PLACEHOLDER_GATE` = `legacy` |
  `issuer`. master hotfix default `legacy`; set `issuer` per host in
  `/etc/srvctl/letsencrypt.conf`. After the fleet runs `issuer`, a follow-up
  commit flips the default and a later one removes `legacy`. Branch default is
  `issuer`. `legacy` only keeps the placeholder rule as it is today; hotfix A
  still changes behaviour on install, whatever the setting (see acceptance A).

## Phase 0 — read-only inspection

New command `sc cert-inspect` (`modules/letsencrypt/commands/cert-inspect.sh`,
`## @en` hint, `root_only`, guard `[[ $SRVCTL ]] || exit 4`). It gets the
resolved environment from the normal init (configs, `$SC_DATASTORE_DIR`) but
runs **no** regenerate hooks; it calls `letsencrypt_main --inspect`, under the
same run lock (`flock -w 60`; report "busy" on timeout).

`letsencrypt.js --inspect` requirements:
- No certbot, no `letsencrypt_deploy`, no rootfs writes, no `writeStatus`, no
  throttle-state or activation-state writes, no handover transitions.
- Handover state is loaded read-only; `begin` (journal replay) is skipped. If
  the journal holds unreplayed operations, report that and mark the wildcard
  verdicts "uncertain".
- Bypass reconstruction: a new pure `AcmeRun.inspectNames(served)` runs the
  same inputs through `plan.evaluate` as `evaluateNames` and collects only
  `result.http01 === "bypass"` and `result.retire`; it never calls `runOp`,
  `setState`, `store.save` or `deployRootfs`. Then `computeGate`. (master has
  no DNS-01 path, so no bypass there.)
- Every datastore cert is evaluated with **both** rules and printed side by
  side — live rule (`SC_ACME_PLACEHOLDER_GATE`) and `issuer` rule — so the
  backlog is visible while the live gate is still `legacy`.
- Per domain: classification `kind` and `daysLeft` (1a); verdict (`ok`,
  `issue`, `renew`, `repair`, `wildcard`, `dns-elsewhere`, `no-dns`,
  `backoff`, `ineligible`); current cert issuer and notAfter; and its place in
  the throttle order (group, cap-exempt).
- Totals: demand = domains whose DNS points at this host. Record
  `openssl version`, `node --version`, `$SC_DATASTORE_DIR`. Across hosts the
  operator deduplicates by domain (shared datastore copies are not independent
  demand).
- Tests: running `--inspect` against a fixture tree leaves every file
  byte-identical (checksum before/after), including handover and throttle
  state.

## WP-CERT-1 — eligibility, staging, throttling (master hotfix, then branch)

**1a classification, separate from renewal timing**
(`http01lib.classify(text, {staging})`), used by `check_datastore_cert`, the
lineage check in `check_container_domain` and, on the branch, the `hostPath`
"existing" check.
- `kind`, judged without looking at expiry:
  - `malformed`: does not parse, or has no leaf;
  - `placeholder`: D-CERT-1, only when the gate is `issuer`;
  - `staging`: staging issuer while not in the staging trial;
  - `chain-repair`: a real leaf, but another block in the bundle has expired;
  - `real`: none of the above.
- `daysLeft`: days until the leaf's notAfter (negative once expired).
- A cert **needs work** unless `kind == real` and `daysLeft >= 7`. What work
  is needed:
  - `chain-repair`: rebuild the bundle from the lineage when the lineage is
    `real` with `daysLeft >= 7`. No certbot call, no cap use. Otherwise it is
    treated as `real` with its `daysLeft` (renew).
  - `real` with `daysLeft < 7`, including expired: renew, scheduling group 1
    (1d).
  - `placeholder`, `staging`, `malformed`, missing: issue, scheduling group 2.
- A cert that needs work makes the check return false, and evaluation
  **continues** toward issuance (DNS, eligibility, throttle); it never ends in
  "skip".
- The lineage check deploys without certbot only when the lineage cert is
  `real` with `daysLeft >= 7`.

**1b staging trial** (D-CERT-5)
- New root-only command `sc cert-staging-trial DOMAIN...`
  (`modules/letsencrypt/commands/cert-staging-trial.sh`, guard `exit 4`). It
  takes the run lock and calls `letsencrypt_main --staging-trial DOMAIN...`
  with `SC_ACME_STAGING_TRIAL=true` exported to that node process only.
- `--staging-trial` runs container http-01 only, for the named domains:
  - certbot gets `--test-cert` and `--config-dir/--work-dir/--logs-dir` under
    `/var/srvctl3/acme/staging/`, and `get_le_dir` reads that `live/`;
  - the only deploy target is `/var/srvctl3/acme/staging/deploy/<domain>.pem`;
  - throttle state goes to `/var/srvctl3/acme/staging/http01-state.json`, so
    staging failures never delay production;
  - it skips everything else: `AcmeRun` construction, journal replay, DNS-01,
    `hostPath`, `finishLeaving`, activation, `writeStatus`.
- With either staging variable set (config or inherited environment), every
  command, the trial included, stops in core init with exit 45, and
  `letsencrypt.js` refuses on its own as well (D-CERT-5 guards 1 and 2).
- Staging detection: issuer contains `(STAGING)`, as LE staging roots and
  intermediates do.
- Production run with a staging cert already present:
  - in `datastore/cert`: classified `staging`, replaced on issuance;
  - in a production lineage: classified `staging`, and that domain's certbot
    call adds `--force-renewal`, so `--keep-until-expiring` cannot keep it.
- Tests:
  - certbot argv for the trial and for production;
  - **complete entry points through `srvctl.sh`**, with certbot and
    `systemctl` stubbed so each "issues" a staging-issuer cert:
    - (1) the flag set in a fixture `/etc/srvctl/*.conf`, then each of
      `regenerate`, `http-redirect`, `https-redirect`, `override-in-address`,
      `add-ve` and `cert-staging-trial`: exit status 45. Marker hooks prove
      that nothing ran after the check: a root custom module (first in
      `SC_MODULES`) with a `pre-init-regenerate` hook and a `pre-init` hook,
      and a shipped-module `pre-init` marker. The case is run twice, once
      with the letsencrypt module enabled and once with its
      `module-condition.sh` returning false;
    - (1b) the same with the variable only in the inherited environment;
    - (2) `sc cert-staging-trial` with no flag in config: succeeds;
    - (3) guard 2 on its own: `letsencrypt.js` started with the variable set
      outside `--staging-trial` exits non-zero before any phase.

    For each, checksum every production destination before and after:
    `datastore/cert` including `wildcard/`,
    `/var/srvctl3/acme/{bundles,incoming}` and the handover state, the rootfs
    `pki/tls` files, `/var/haproxy`, `/etc/letsencrypt/live`, and the service
    cert copies (`/etc/postfix`, …). They must be identical; only the staging
    dirs may change, and only under (2). Files outside these destinations
    (logs, module cache) are not asserted;
  - **pre-existing staging cert with no successful replacement**, file level
    (D-CERT-7): staging certs placed in `datastore/cert/<d>.pem`,
    `datastore/cert/wildcard/`, `/etc/srvctl/cert/<d>/`, an installed
    `/etc/postfix/crt.pem` and a container `localhost.crt`, and already
    copied to `/var/haproxy`; certbot stubbed to fail. After `regenerate`:
    - none is in `/var/haproxy`, and the fan-out copied none;
    - the service and container copies hold the fallback;
    - each rejection is logged, and no other served cert changed;
    - the variant where the only cert is staging installs
      `000-srvctl-fallback.pem`, so the directory is never empty; a later run
      with an ordinary cert back removes the fallback; a run where the
      fallback is the only file present still counts the set as empty and
      keeps it.

    Same test on master's copy path;
  - **fallback generator** (`sc_fallback_cert`, file level):
    - a staging cert pre-placed at `/etc/srvctl/cert/$HOSTNAME/$HOSTNAME.pem`
      is never chosen as the service fallback;
    - a staging or mismatched cert pre-placed in the dedicated fallback
      directory, or in `/srv/<C>/cert`, is moved aside and a checked
      self-signed cert is installed;
    - a generator stubbed to fail twice installs nothing and logs an error;
  - **service activation** (stubbed `systemctl`, both branches):
    - postfix and perdition hooks: one restart per `regenerate` (never two);
      fingerprint recorded only under the success rule;
    - **failed restart command, unit still active**: `systemctl restart
      postfix` returns non-zero while `is-active` still says active (the old
      process) → no record, error logged; the next `regenerate` succeeds and
      records;
    - perdition, **early unit fails while the last succeeds**: `imap4s`'s
      restart command returns non-zero but the unit stays active (old
      process), `imap4` and `pop3s` succeed → aggregate non-zero, no record,
      the hook still returns 0. The same with `imap4s` left inactive. In both
      cases the next `regenerate` restarts all three and records once every
      command succeeded and every unit is active;
    - master hooks: a staging `crt.pem` is replaced by the refresh before the
      restart;
    - gui step: active with a changed fingerprint → one restart, then
      recorded; unchanged → no restart; first run with no record and gui
      active → one restart;
    - gui **stopped by the operator** (inactive, not pending) with a staging
      cert → the cert file **is replaced** (step 1), gui is **not** started,
      and the record is unchanged;
    - gui failure **before the stop** (restart command fails, unit stays
      active) → `pending` kept, no record, error logged, old process still
      up; next run retries and records;
    - gui failure **after the stop** (startup fails, unit left inactive) →
      `pending` kept, error logged; next run retries **although the unit is
      inactive**, succeeds, records and clears `pending`;
    - **crash** after `pending` is written and before the result → the next
      run treats the entry as pending and retries;
    - **operator stop after a failed attempt**: `pending` set, then the
      operator stops gui → the next `regenerate` restarts it (documented
      behaviour). Then: `pending` set, operator stops gui **and runs
      `sc cert-pending-cancel gui`** before the next `regenerate` → gui stays
      stopped, `pending` is cleared, the record is unchanged; starting gui by
      hand later triggers a normal activation on the next `regenerate`;
    - `sc cert-pending-cancel` with nothing pending → no change, exit 0; an
      unknown service name → error, non-zero exit;
  - **running-listener tests (real processes, not stubs)**. File-level tests
    cannot show what a live listener serves. These run real haproxy, httpd and
    postfix processes, are skipped (reported) where the binary is missing,
    and are **required** on the pilot VM. The expectation depends on the
    failure:
    - a **rejected reload or config check** keeps the old process, which goes
      on serving the old certificate until activation succeeds;
    - a **restart that fails after the stop** leaves the service down.

    In both cases the error is logged every run, and the retry brings the
    replacement into service:
    - haproxy, in the selftest: a non-root haproxy on a high port, with the
      real rendered bind line pointing at a fixture crt directory. A test CA
      whose name contains `(STAGING)` issues the served cert. Assert with
      `openssl s_client` against the live port:
      - (a) staging cert with a valid replacement → after sync + reload the
        replacement is served;
      - (b) staging cert with **no** replacement and nothing else in the
        directory → the fallback is served, and the reload succeeded;
      - (c) activation failure (invalid config injected, so `haproxy -c`
        fails) → no reload and no restart; the process stays up and **still
        serves the staging cert**; the alert is logged and the record kept.
        After the injection is removed, the next run reloads and the fallback
        is served;
    - httpd, on the pilot VM: a test container with a staging `localhost.crt`,
      then `regenerate`; `openssl s_client` directly against the container
      shows its self-signed fallback. Failure case: make the reload fail once
      (e.g. a broken `ssl.conf` include) → the container **still serves the
      staging cert** and an error is logged; after restoring it, the next run
      reloads and the fallback is served;
    - postfix, on the pilot VM: staging `crt.pem` installed →
      `openssl s_client -starttls smtp -connect <host>:25` shows the fallback
      after `regenerate` (both branches; activation is the postfix hook's
      restart). Two failure cases:
      - **rejected before the stop** (the restart job made to fail while
        postfix keeps running) → postfix **still serves the staging cert**,
        no record, error logged;
      - **startup failure after the stop** (e.g. a temporarily broken
        `main.cf` include) → postfix is **down** (the connection is refused),
        no record, and the error is logged; the command aborts as today
        (existing FIXME in `restart_postfix`).

      In both cases, after the cause is removed, the next `regenerate`
      restarts postfix, the fallback is served and the fingerprint is
      recorded;
    - perdition, on the pilot VM: one unit made to fail at startup while the
      others restart → no record, error logged, the failed listener down; the
      next `regenerate` activates all three units and records;
  - production run with a staging cert in (a) `datastore/cert` and (b) the
    lineage: both reach issuance, (b) with `--force-renewal`;
  - a staging-issuer bundle offered to `acmerun.candidate` and to
    `wildcard_servable_managed` is rejected.

**1c caller-level tests** (extend `datastore-cert.test.mjs` and
`http01lib.test.mjs`):
- key-only file → `malformed`, needs work;
- valid CA-issued leaf with 30 days left → `real`, no work;
- real leaf with 6 days left → renew, group 1, not cap-exempt;
- real leaf with 2 days left → renew, group 1, cap-exempt;
- exact boundaries, where `daysLeft = (notAfter − now) / 86400` is a real
  number and the rules are strict `< 7` and `< 3`: exactly 7 days → no work;
  7 days − 1 s → renew; exactly 3 days → renew, not cap-exempt; 3 days − 1 s →
  cap-exempt (the tests inject `now`);
- expired real leaf → renew, group 1, first in order, cap-exempt;
- issuer == subject signed by another key → `placeholder` (pins D-CERT-1);
- real leaf plus an expired appended root → `chain-repair`, rebuilt from a
  good lineage without certbot;
- staging leaf → `staging` in production;
- garbage → `malformed`, and evaluation continues toward issuance;
- gate `legacy`: the srvctl placeholder classifies exactly as today. This
  proves only that `legacy` keeps the placeholder rule unchanged, not that
  hotfix A changes nothing.

**1d fair throttling with backoff** (`http01lib`)
- State per domain in `/var/srvctl3/acme/http01-state.json` (the staging trial
  uses its own file): `lastAttempt`, `failures`, `nextAttempt`, `inFlight`,
  `fingerprint` (DNS A set + datastore cert sha256). Every write goes through
  `secureReplace`, under the run lock (1f).
- Reservation before certbot runs: write `inFlight: true`, `lastAttempt: now`,
  `failures + 1`, `nextAttempt: now + backoff(failures + 1)`. Then persist the
  outcome: success resets the entry, failure keeps the reservation's values
  and clears `inFlight`. A crash between the two leaves a counted failure with
  its backoff, so interrupted runs cannot keep retrying the same domain. The
  next run logs any leftover `inFlight`.
- Backoff after a failure: 1h, 2h, 4h … max 24h; group 1 is capped at 6h. It
  resets on success or when the fingerprint changes.
- Order after de-duplicating domains across containers:
  1. group 1 (`real`, `daysLeft < 7`), lowest `daysLeft` first, so expired
     certs come first;
  2. group 2 (placeholder, staging, malformed, missing), least recently
     attempted first.
  Domains still in backoff are skipped.
- Cap `SC_ACME_HTTP01_MAX_PER_RUN` (default 10) counts certbot calls per host
  per run. Group 1 with `daysLeft < 3` (expired included) is exempt from the
  **cap only, never from backoff**. `chain-repair` rebuilds never count.
- The cap reduces bursts but does not guarantee rate-limit safety (limits also
  apply per account and per registered domain,
  https://letsencrypt.org/docs/rate-limits/); Phase 0 numbers set the pace.
- The 7-day window, the 3-day exemption and the 6h group 1 backoff ceiling
  are the initial policy (agreed in round 4). They reduce delay and bursts; they
  do **not** guarantee renewal before expiry when failures persist (DNS moved,
  challenge path broken, CA outage). The inspect output and the error log are
  how an operator sees such a domain.
- master: explicit `export` of `SC_ACME_PLACEHOLDER_GATE` and
  `SC_ACME_HTTP01_MAX_PER_RUN` (no loop there; the staging flag is retired,
  D-CERT-5).

**1e master only — drop DST Root CA X3**: a new bundle is privkey + fullchain,
and `install_acme` removes the stale `/etc/letsencrypt/ca.pem`. Bundles
containing the expired root are rebuilt without ACME calls when a usable local
lineage exists (`real`, `daysLeft >= 7`, on this host). Other cases are
reported and follow the issuance or renewal policy:
- no lineage on this host (for example a bundle in a shared datastore issued
  by another host): reported. It classifies `chain-repair` and is repaired
  only where its lineage lives, or renewed by the normal policy if this host
  serves the domain;
- lineage expired or within 7 days: renewal (group 1, normal throttle);
- placeholders and admin-wildcard copies never contained the root; they are
  unaffected.

The rebuilds may span several runs (throttled renewals, other hosts). The
expected outcome is one successful haproxy reload once the changed set is
complete, not an unconditional reload on install.

**1f master — run lock**: `letsencrypt_main` wraps node in
`flock -w 600 "${SC_LETSENCRYPT_LOCK:-/run/srvctl-letsencrypt.lock}"` exactly
as the branch does. Port `selftest/runlock.test.sh` to master and add an
overlap test: two concurrent runs over one throttle state → one waits, no
duplicate certbot calls (stubbed), the final state holds both runs' updates.

**Tests for 1d**:
- the first N failing domains do not starve later ones over consecutive runs;
- backoff schedule, the 6h group 1 cap, and reset on success or on a
  fingerprint change;
- cap boundary: exactly N calls, the N+1st deferred;
- 6-day real cert counts against the cap; 2-day and expired real certs exceed
  it but still respect backoff; `chain-repair` never counts;
- de-duplication across two containers claiming one domain;
- crash and resume: abort after the reservation, before certbot returns → the
  next run sees the counted failure, skips the domain until `nextAttempt`, and
  logs the leftover `inFlight`;
- staging-trial failures leave the production state file untouched;
- unreadable state file → treated as empty with an error, never a crash.

## WP-CERT-2 — certificates of removed domains

**2a one name expansion**: `cert_names(C)` = `container_domains(C)` ∪ `{C}` ∪
`{normalize_container_domain(C)}` ∪ (`C` dotless ⇒ `C.<company-domain>`).
`cluster_cert_names()` = ∪ `cert_names(C)` over all containers ∪ every cluster
host fqdn. Exposed as `get container "$C" cert_names` and
`get cluster cert_names`.
- branch: `generators.mjs` + `main.mjs`.
- master: `lib.js` (`container_cert_names`, `cluster_cert_names`) + `main.js`
  dispatch for both getters.
- Test: the two functions agree (every `cert_names(C)` ⊆ cluster set while C
  exists).

**2b removal** (`remove-ve.sh`, `destroy-ve.sh`, shared helper in
`containers/libs/`): before `del container`, `candidates=$(get container "$C" cert_names)`;
after `del` succeeds, `retained=$(get cluster cert_names)`. **Both lookups
must succeed** (exit 0, candidates non-empty); otherwise log an error, delete
no certificate, and let the container removal continue (2c/2d stop serving the
orphans). Delete `cert/<name>.pem` for candidates − retained; never touch
`cert/wildcard/`. Extend `remove-cert.test.sh`: aliases, altnames, subdomains,
normalized and fan-out names deleted; a name still used by another container
survives; failed `del` → nothing deleted; failed pre-lookup → nothing deleted;
failed post-deletion retained lookup → nothing deleted.

**2c branch — filter in `sync_haproxy_certificates` step 2**: serve a datastore
cert only if its name is in `get cluster cert_names`. Lookup failure (non-zero
or empty) ⇒ no filter (serve as today) + error; never prune on a guess.
Tests: orphan present in both `datastore/cert` and `/var/haproxy` is removed
from `/var/haproxy`; alias, altname, subdomain, fan-out and host certs survive;
admin certs unaffected; failed lookup changes nothing.

**2d master — retained-set-driven sync in `regenerate_haproxy_conf`**:
- Desired set = every admin cert (`/etc/srvctl/cert/*/*.pem`, basename, as
  today) ∪ datastore certs whose name is in `get cluster cert_names`, minus
  any cert for which `cert_is_staging` is true. The staging rejection and the
  empty-set fallback are already in the copy path from hotfix A (D-CERT-7) and
  apply even when the lookup fails.
- Copy desired files as today (`cp -u`); do **not** copy datastore certs
  outside the set.
- Remove every `/var/haproxy/*.pem` not in the desired set.
- Lookup failure ⇒ old behaviour (copy all, remove nothing) + error.
- Datastore orphan files themselves stay on disk (logged); 2b handles new
  removals.
- Tests (standalone on master): orphan present in both directories is removed
  from `/var/haproxy`; admin cert without a datastore source survives; retained
  alias survives; failed lookup changes nothing.
- Activation: WP-CERT-5 haproxy part reloads after the prune.

## WP-CERT-3 — placeholder creation in `add_ve` (both branches)

Move the copy into `add_ve_certificate` (inside the `/etc/pki/tls` check);
`mkdir -p` + `install -m 600` into `$SC_DATASTORE_DIR/cert` (fixes F3, F4, F5
and the placeholder mode); plain `cat` for `resolved.conf`; drop the FIXME.
Test: stubbed `add_ve_certificate` with and without `/etc/pki/tls` → placeholder
exists (0600, no ANSI line) only when the cert was created.

## WP-CERT-4 — private-key permissions, preserving container ownership

- `http01lib.secureReplace(file, data, mode, owner)`: temp name
  `<file>.tmp.<pid>.<random>`, `openSync(tmp, "wx", mode)` (exclusive),
  `fchownSync(fd, uid, gid)` when `owner` is given, `fchmodSync(fd, mode)`,
  write, `fsyncSync`, close, `renameSync`, fsync the directory; unlink the temp
  on any error. On the branch `acmerun.atomicWrite` becomes a thin wrapper over
  it, so `deployRootfs` and the host path get the same contract.
- Host-side files (`datastore/cert`, bundles): `secureReplace(..., 0o600)`.
- Container rootfs files: owner = `stat` of the target directory
  (`private/` or `certs/`, the shifted container root); if the directory is
  owned by host root (no shift), owner = the existing file's owner. Modes:
  `localhost.key`, `*.pem` 0600, `localhost.crt` 0644.
- `add_ve_certificate`: `install -m 600` for `localhost.key` (rootfs not yet
  running; `PrivateUsersChown=true` shifts at first start). Staging check:
  httpd runs and reads the key after `add-ve`.
- `domaincertlib.sh`: generate under `umask 077`; delete `config.txt`,
  `random.txt`, `.key.org` afterwards; `chmod 600` key/pem on every return
  path, including the existing-certificate early returns.
- One-time: `set_permissions` adds `chmod 600` on
  `/srv/*/cert/*.{key,pem,key.org}` and removes `/srv/*/cert/config.txt`;
  inside a rootfs only modes change, owners stay with
  `check_container_pki_ownership`.
- Tests: an existing 0644 target ends 0600; shifted-uid directory → new file
  carries that uid/gid; host-root directory → existing owner kept; injected
  write failure → target unchanged and no temp file left; leftover temp name
  from a crash does not block the next write; `domaincertlib` early-return path
  leaves 0600 files.

## WP-CERT-5 — activation with retry

- haproxy: the branch already reloads on a changed served set, and keeps the
  old record when a reload fails so the next run retries
  (`haproxy_certificates_changed` / `haproxy_record_reloaded`). The listing
  hashes whole files, so chain-only changes count. Port both to master
  (~30 lines) and replace master's unconditional hourly skip.
- Container httpd (`http01lib.activateContainers`), run at the end of every
  normal `letsencrypt.js` run under the lock (not in `--inspect` or
  `--staging-trial`):
  - The activation fingerprint is the sha256 over every normalized
    certificate block of `/etc/pki/tls/certs/localhost.crt`, in order, plus
    the sha256 of `/etc/pki/tls/private/localhost.key`. It covers the whole
    deployed chain and the key, not only the leaf.
  - For every container with both files and an active httpd
    (`systemctl -M <C> is-active httpd`): when the fingerprint differs from
    `/var/srvctl3/acme/activated.json[C]`, run `systemctl -M <C> reload httpd`.
    On success record the fingerprint (`secureReplace`); on failure log an
    error and leave the record, so the next run retries.
  - Containers without the files, or without an active httpd: no reload, no
    record change (retried once httpd runs).
  - Fingerprint-based, so it covers `letsencrypt_deploy`,
    `acmerun.deployRootfs`, `chain-repair` rebuilds and any other writer.
  - First run after rollout: no record yet ⇒ one graceful reload of each
    container that has the certificate files and an active httpd.
- Tests (stubbed `systemctl`):
  - reload failure, then success on the next run;
  - unchanged fingerprint → no reload;
  - inactive httpd → no reload, no record;
  - a `deployRootfs`-style write triggers a reload;
  - **chain-only change**: same leaf and key, intermediate replaced or an
    expired appended root removed → reload.

## Sequence

| Step | Where | Content |
|---|---|---|
| 1 | branch | commit the current-tree gate fix and removal cleanup as-is |
| 2 | master worktree | hotfix A: `http01lib.js` + tests, 1a (gate default `legacy`), 1b, 1c, 1d, 1e, 1f, `cert-inspect`, core-init staging guard (D-CERT-5), D-CERT-7 for haproxy (copy-path rejection, empty-set fallback, `haproxy -c` before reload) and service TLS (`sc_fallback_cert`, `service_certs_activate`, `cert-pending-cancel`, restart helpers under the success rule), WP-5 haproxy |
| 3 | master | hotfix B: WP-2a, 2b, 2d |
| 4 | master | hotfix C: WP-3, WP-4, WP-5 container part |
| 5 | branch | port hotfix A (identical `http01lib.js`; `inspectNames`; staging refusal in the whole `regenerate` path; `atomicWrite` → `secureReplace`) |
| 6 | branch | WP-2a–c |
| 7 | branch | WP-3, WP-4, WP-5 container part |

master receives every package (A–C), so no production bug waits for the branch
merge. The gate stays `legacy` on every host until A, B and C are all
installed there.

## Verification

### Automated (every hotfix and branch step)
- Run: `http01lib.test.mjs`, `datastore-cert.test.mjs`, `runlock.test.sh` and
  the overlap test, the complete-entry-point staging test (1b),
  `remove-cert.test.sh`, the haproxy sync/prune tests, the `cert-inspect`
  no-mutation test, and the WP-3/4/5 tests listed above.
- `node --check` on each JS file; shellcheck on each changed `.sh`.

### Staging trial (any host, after hotfix A)
- Use a test domain that no wildcard covers.
- `sc add-ve`, then point its DNS at the host → `sc cert-staging-trial <domain>`.
- Expect a lineage under `/var/srvctl3/acme/staging/` and a bundle in
  `/var/srvctl3/acme/staging/deploy/`.
- Production destinations (the list in 1b) unchanged, by checksum.
- With `SC_LETSENCRYPT_STAGING=true` in a conf file, `sc regenerate` exits 45
  and no certificate destination changes; the same with the line removed runs
  normally.

### Acceptance A (pilot host, gate still `legacy`)
Hotfix A changes behaviour on install even with `legacy`: bundles with the
expired DST root are repaired where possible; the staging flag is refused in
core init; staging certs are rejected from the haproxy and service TLS
desired sets and leave live service once activation succeeds; throttling and
the run lock apply; haproxy reloads (after `haproxy -c`) when the served set
changes. Container httpd is **not** covered
by A: its staging rejection comes with the activation pass in hotfix C (see
acceptance C). Check:
- the haproxy, postfix and perdition running-listener checks from WP-CERT-1b
  pass on the pilot: staging cert with a replacement, with none, a rejected
  reload or restart (old cert still served), and a startup failure after the
  stop (service down), each followed by a successful retry;
- `sc cert-inspect` runs, changes nothing, shows the `issuer`-rule backlog,
  and lists every `chain-repair` bundle as either **local repair** (usable
  local lineage) or **ACME work** (no local lineage, or lineage due);
- after the next `regenerate`:
  - every local-repair bundle's served chain has no expired block (no DST
    Root CA X3), checked through haproxy with `openssl s_client`, and no
    certbot call was made for them;
  - every ACME-work bundle is reported, and is either renewed within the
    throttle or still waiting, with its reason logged;
- haproxy reloaded successfully once after the changed set was complete, and
  not again on an unchanged hourly run;
- throttle state exists; the only ordering changes are renewals.

### Acceptance B (same pilot, gate still `legacy`)
- A historical orphan (present in both `datastore/cert` and `/var/haproxy`)
  leaves `/var/haproxy` after `regenerate`; admin certs and retained aliases
  stay.
- Remove a test container with an alias and a subdomain: all its names leave
  `datastore/cert`, and `/var/haproxy` on every serving host after their next
  regenerate; a cert shared with another container survives.

### Acceptance C (same pilot, gate still `legacy`)
- Existing key files under `/srv/*/cert` and `datastore/cert` are 0600 after
  `update-install`.
- A fresh `sc add-ve`: placeholder 0600, no ANSI line, httpd running with a
  readable `localhost.key` owned by the shifted container root.
- `activated.json` gets filled; a forced reload failure is retried on the next
  run.
- The container httpd running-listener check from WP-CERT-1b passes: a
  staging `localhost.crt` is replaced by the container's self-signed fallback
  and served after the reload, including the failed-reload-then-retry case.
  Only from this point is D-CERT-7 (rejection, then removal from live service
  after successful activation) claimed for every listener.

### Pilot with the fixed gate (after A–C on that host)
- Set `SC_ACME_PLACEHOLDER_GATE=issuer`, then `sc cert-inspect` → note the
  demand → `sc regenerate`.
- For each issued domain:
  - through haproxy, `openssl s_client -connect <host-ip>:443 -servername <domain>`:
    the served chain's fingerprints match the bundle in
    `datastore/cert/<domain>.pem` (method from commit 3d8fa58);
  - direct, `openssl s_client -connect <container-ip>:443 -servername <domain>`:
    the chain matches `localhost.crt`;
  - no expired block in either chain;
  - `localhost.key` is 0600, owned by the shifted container root, httpd
    running.
- Watch hourly runs until the waiting count is zero.

### Production rollout
1. Install hotfixes A, B and C on every host, gate `legacy`, checking
   acceptance A–C on each.
2. Run `sc cert-inspect` on every host and set the cap from the combined
   de-duplicated demand.
3. Flip the gate to `issuer` host by host, repeating the fixed-gate pilot
   checks on each.

## Out of scope (separate package)

`openssl verify` exit-2 early return in `domaincertlib.sh`, 1024-bit DH params
(`servicecertlib.sh`), root CA expiry and stale `.p12` (`calib.sh`), and a
DNS-01 staging trial entry point (D-CERT-5).
