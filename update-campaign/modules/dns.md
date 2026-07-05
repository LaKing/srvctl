# Module dns — v3 fact sheet (commit 988c38c)

## Purpose
Scans public DNS (via Google 8.8.8.8) for every domain of every container and stores the
A/AAAA/MX/NS records plus a scan-state timestamp under `containers[name].dns[domain]` in the
datastore `containers.json`. This data is consumed by the letsencrypt module
(`modules/letsencrypt/letsencrypt.js:282-292`) to decide whether a domain's A record points at
this host before attempting certificate issuance. A secondary hook forces 8.8.8.8 as the host's
global DNS server during `update-install`.

The module exposes NO CLI commands (no `commands/` directory). It consists of one bash lib
function (`dns_scan`), one Node.js scanner (`dns-scan.js`), and two hooks.

## Activation
`modules/dns/module-condition.sh:3` simply sources
`modules/containers/module-condition.sh`, so the dns module is enabled exactly when the
containers module is: host is not `localhost.localdomain`; `$SC_HOSTNET` is set or
`/etc/srvctl/data` exists; not running inside a container (`systemd-detect-virt -c` is not
`systemd-nspawn`/`lxc`); and `$HOSTNAME` appears quoted in `/etc/srvctl/hosts.json`. It is also
force-enabled when `$CMD == update-install` with an argument. Conditions are evaluated in a
subshell (`commonlib.sh:436`), so the `readonly SC_VIRT` in the sourced file cannot clash, and
the result is cached in `modules.conf` as `SC_USE_DNS=true|false`.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | (module has no `commands/` directory) | - |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/regenerate.sh` | `run_hook regenerate` — fired by `sc regenerate` (`modules/containers/commands/regenerate.sh:30`), by `regenerate_all_hosts` (`modules/containers/libs/regenlib.sh:10`), and after `add-ve` / `add-ve-user` / `add-network-ve` / `add-codepad` | Calls `dns_scan` (no args), i.e. runs `dns-scan.js` synchronously over all containers/domains. |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` — fired near the end of `sc update-install` (`modules/srvctl/commands/update-install.sh:83`) | Echoes "Set 8.8.8.8 as DNS server globally.", overwrites `/etc/systemd/resolved.conf` with the single line `DNS=8.8.8.8`, then `run systemctl restart systemd-resolved` and `run systemctl status systemd-resolved --no-pager -n 30`. |

Hooks are sourced into the main shell by `run_hook` (`commonlib.sh:85-108`), followed by
`exif "$dir hook '$hook' failed"` — a nonzero exit from `dns-scan.js` aborts the whole srvctl run.

## Libs
`libs/bashlib.sh` (sourced whenever `SC_USE_DNS=true`, via `load_libs`, `commonlib.sh:47-66`):

- `dns_scan` (`bashlib.sh:3-8`): prints `msg "DNS scan"` then runs
  `/bin/node "$SC_INSTALL_DIR/modules/dns/dns-scan.js" $*` (unquoted `$*`, shellcheck-disabled).
  Grep shows no caller outside this module (`hooks/regenerate.sh:3` is the only call site);
  `dns-scan.js` reads `process.argv[2]` into `CMD` (dns-scan.js:16) but never uses it.

`dns-scan.js` (invoked by `dns_scan`, not sourced):
- `scan_container(name)` / `scan_container_domain(name, domain)` / `scan()` — resolve A, then
  (nested inside the A success callback) AAAA, MX, NS for each domain from
  `datastore.container_domains(name)` (name + `www.`name + aliases + altnames, each with `www.`
  prefix — `modules/datastore/lib.js:683-720`).
- Skip rule: a domain whose last state was `ENOTFOUND`, `ETIMEOUT`, or `ESERVFAIL` is re-scanned
  at most hourly (3600 s window, dns-scan.js:105-109); all other domains are re-scanned on every run.
- On process exit the entire in-memory `containers` object is written back to
  `$SC_DATASTORE_DIR/containers.json` pretty-printed with 2-space indent (dns-scan.js:155-157).

## Config & templates
- (no `conf/` directory in this module)
- `hooks/update-install-host.sh:5` generates `/etc/systemd/resolved.conf` in-place on the host
  with content exactly `DNS=8.8.8.8` (single line, no `[Resolve]` section header).

## State touched
- **Datastore**: `$SC_DATASTORE_DIR/containers.json` — reads all container objects (via
  `modules/datastore/lib.js`), writes `containers[name].dns[domain] =
  { A:[], AAAA:[], MX:[], NS:[], timestamp:{ time:<epoch-seconds>, state:"OK"|"UNKNOWN"|<node
  dns err.code> } }`, and rewrites the whole file on exit. `SC_DATASTORE_DIR` may be the
  gluster-shared dir (`/var/srvctl3/gluster/srvctl-data`) or `/var/srvctl3/datastore`
  (`modules/datastore/hooks/pre-init.sh`, `datalib.sh:110-124`).
- **Host files**: `/etc/systemd/resolved.conf` (overwritten by update-install-host hook).
- **systemd units**: restarts `systemd-resolved` (update-install-host hook).
- **Network**: outbound DNS queries to `8.8.8.8` (dns-scan.js:63) for every container domain on
  every regenerate.

## Dependencies
- Core: `msg` (lablib.sh), `run` (lablib.sh:93), `exif`/`eyif` via `run_hook`/`run`,
  `$SC_INSTALL_DIR`, `load_libs`/`run_hook` machinery (commonlib.sh).
- Modules: **containers** (condition sourced verbatim; regenerate lifecycle),
  **datastore** (`modules/datastore/lib.js` for `containers` and `container_domains`; exported
  `SC_DATASTORE_DIR` env set by `init_datastore`, `datalib.sh:124`). Consumer: **letsencrypt**
  reads `containers[name].dns[domain].A/NS` (`letsencrypt.js:282-299`).
- JS: `/srv/srvctl/lablib.js` (`msg`, `ntc`); Node core `dns.Resolver`, `fs`, `os`.
- External binaries: `/bin/node` (hardcoded path, bashlib.sh:7), `systemctl`,
  `systemd-detect-virt` (via sourced condition).

## Bugs & smells
- **high** `modules/dns/hooks/update-install-host.sh:5` — Overwrites `/etc/systemd/resolved.conf`
  with the bare line `DNS=8.8.8.8` and no `[Resolve]` section header. systemd's config parser
  ignores assignments outside a section ("Assignment outside of section. Ignoring."), so the
  advertised change ("Set 8.8.8.8 as DNS server globally.") never takes effect, while the stock
  resolved.conf is destroyed on every `sc update-install` on every host.
- **medium** `modules/dns/dns-scan.js:93-96` — `o.A/o.AAAA/o.MX/o.NS` are reset to `[]` *before*
  the hourly-skip check (lines 105-109) and before the async resolution completes. A transient
  resolver failure (e.g. `ETIMEOUT` from 8.8.8.8, error path line 114-120) leaves previously
  good records wiped in the containers.json written at exit; letsencrypt then sees `A=[]` and
  refuses issuance/renewal ("no A record", `letsencrypt.js:284-292`) until a later successful scan.
  Skipped problematic domains likewise get their stored records zeroed each run.
- **medium** `modules/dns/dns-scan.js:155-157` — The exit handler unconditionally
  `writeFileSync`s the entire `containers` object over `$SC_DATASTORE_DIR/containers.json`, with
  no lock and no read-only-datastore check (unlike `write_containers`,
  `modules/datastore/lib.js:129-137`, which at least tests `SC_DATASTORE_RO`). Any concurrent
  containers.json modification during the scan window — another srvctl command on this host, or
  another cluster host when the datastore is the shared gluster mount — is silently clobbered
  with the stale copy loaded at startup.
- **medium** `modules/dns/dns-scan.js:126-139` — AAAA/MX/NS lookups run only inside the
  `resolve4` success callback. Domains with no A record (IPv6-only → `resolve4` errors `ENODATA`)
  never get AAAA/MX/NS data at all, their state is recorded as the error code, and since
  `ENODATA` is not in the skip list (lines 106-108) they are fruitlessly re-queried on every run.
- **low** `modules/dns/dns-scan.js:63` — Resolver hardcoded to the single upstream `8.8.8.8`
  (bypassing the system resolver and the local `named` module). On networks where Google DNS is
  unreachable, every domain flips to `ETIMEOUT`, records get wiped (see above), and letsencrypt
  is blocked cluster-wide; there is no configuration knob.
- **smell** `modules/dns/dns-scan.js:8-10,33-50,53-58` — dead copy-paste boilerplate: `out(msg)`
  shadows the imported `msg`; `return_value`/`return_error`/`output`, `hosts`/`users`/
  `resellers`/`user`/`container`, `SRVCTL`/`SC_UID0`/`localhost`/`br`/`NOW`/`CMD` are all unused.
  `process.exitCode = 99` (line 27) is unreachable in practice (line 153 always resets to 0).
- **smell** `modules/dns/hooks/regenerate.sh:3` — dns_scan runs synchronously inside every
  regenerate (and thus inside `add-ve` and friends); with many domains the c-ares timeouts make
  container creation noticeably slower for no per-container benefit.

## Polish risks
A rewrite must preserve exactly:
- Datastore schema and file: `containers[name].dns[domain]` object with keys `A`, `AAAA`, `MX`
  (node `resolveMx` objects `{exchange, priority}`), `NS`, `timestamp.time` (epoch seconds,
  dns-scan.js:66,111) and `timestamp.state` with the literal values `"OK"`, `"UNKNOWN"`, or a
  node dns `err.code` string (`ENOTFOUND`, `ETIMEOUT`, `ESERVFAIL`, `ENODATA`, ...)
  (dns-scan.js:111-123). File written to `$SC_DATASTORE_DIR/containers.json` with
  `JSON.stringify(containers, null, 2)` (dns-scan.js:19,156). letsencrypt.js depends on this
  shape (`letsencrypt.js:283-299`).
- Skip semantics: 3600-second window applies only to states `ENOTFOUND`/`ETIMEOUT`/`ESERVFAIL`
  (dns-scan.js:105-109); everything else re-scans every run.
- Domain set scanned: output of `datastore.container_domains()` — container name (only if it
  contains a dot) + `www.` variant + all aliases/altnames each with `www.` variant
  (datastore/lib.js:683-707).
- Output strings: `msg "DNS scan"` (bashlib.sh:4); `"No container for " + domain`
  (dns-scan.js:85); `"Skipping DNS scan on ENOTFOUND|ETIMEOUT|ESERVFAIL <name> <domain>"`
  (dns-scan.js:106-108); `ntc("DNS Scan A record", err.code, err.hostname)` in yellow
  (dns-scan.js:117); `"Set 8.8.8.8 as DNS server globally."` (update-install-host.sh:3).
- Exit codes: `dns-scan.js` exits 0 on any normal run (dns-scan.js:153,159); nonzero exit from
  the hook aborts srvctl via `exif` in `run_hook` (commonlib.sh:104). Datastore lib may
  `process.exit(112)` on unreadable JSON (datastore/lib.js:42-46).
- Hook lifecycle points: dns scan on `regenerate`; resolved.conf write + `systemd-resolved`
  restart on `update-install-host` (whatever v4 decides about the resolved.conf defect, the hook
  timing and restart are observable behavior on production hosts).
- Bash function name `dns_scan` is defined in the global shell namespace when the module is
  enabled; upstream resolver is `8.8.8.8` (dns-scan.js:63, update-install-host.sh:5).

## v4 notes
- Ideal .mjs candidate: the whole module is really one JS scanner plus 3 lines of bash glue. In
  v4, a `dns-scan.mjs` using `dns/promises` + `Promise.allSettled` could resolve A/AAAA/MX/NS
  independently (fixing the IPv6-only blind spot), keep old records on transient errors, and
  update only the `dns` sub-objects it scanned instead of rewriting all of containers.json
  (route writes through a single datastore writer with locking/RO awareness).
- Boilerplate duplication: the env/const/return_value/return_error preamble in dns-scan.js is
  copy-pasted across the JS files of several modules (datastore, letsencrypt, ...). One shared
  ESM datastore/context module would remove it.
- `8.8.8.8` is hardcoded twice (scanner and resolved.conf hook); should become a config value
  (e.g. `SC_DNS_UPSTREAM`), and the resolved.conf hook should write a proper drop-in
  (`/etc/systemd/resolved.conf.d/srvctl.conf` with a `[Resolve]` header) or be dropped/merged
  with the `named` module, which runs a local DNS server the current hook actively bypasses.
- The scan does not need to run synchronously inside `add-ve`/regenerate; a systemd timer or a
  post-regenerate background job would decouple DNS latency from container creation, as long as
  letsencrypt's "no DNS scan yet" ordering expectation is respected.
- The module-condition "source another module's condition" trick works only because conditions
  run in subshells; v4 should express this as an explicit dependency (dns requires containers).
