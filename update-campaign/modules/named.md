# named — v3 fact sheet (commit 988c38c)

## Purpose
Runs BIND (`named`) as the authoritative DNS server farm for all microsite domains in the cluster. At install time it writes `/etc/named.conf`; at every `regenerate` it runs `named.js`, which aggregates `containers.json` from every cluster host (local datastore file + HTTPS fetch from peers), writes per-domain zone files (SOA/NS/A/SPF/DKIM/DMARC/MX/custom records) on masters, writes `/var/named/srvctl.conf` declaring master or slave zones, and restarts `named`. Also carries a **dormant** dyndns subsystem (HTTPS update server + `nsupdate` script) that is explicitly disabled (`install_dyndns` returns early with "dyndns implementation not ready").

## Activation
`module-condition.sh:3-10`: echoes `true` iff `$SC_DNS_SERVER` is exactly `master` or `slave`, else `false`. `SC_DNS_SERVER` originates from the host's `dns_server` key in `/etc/srvctl/clusters.json`, exported into `/etc/srvctl/host.conf` by `modules/containers/host-conf.js:45` (`SC_<KEY>=<value>` for every host key) and sourced by `init.sh`. A commented-out line (`module-condition.sh:11`) shows it once chained to the containers module condition.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| `override-in-address VE [none\|ip]` (`commands/override-in-address.sh`) | "Override the IN A of the container in named DNS server zone file" | `hs_only`; requires `$SRVCTL` (else exit 4); requires container arg; reads container `user`/`reseller` from datastore; if caller is owner/reseller, `sudomize` (re-exec via sudo); then `put container $C override_in_a_ip $OPA` | Datastore write of `override_in_a_ip`; runs `run_hook regenerate_certificates` and `regenerate_haproxy_conf` (haproxy module). Does **not** regenerate named config (see Bugs). Closing comment: "this is actually a setting for all reverse proxies" |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/regenerate.sh` | `sc regenerate` | `msg "Regenerate bind/named DNS server configuration"`; calls `namedcfg` (runs `named.js`), then `restart_named`. Comment notes multi-master restart is not handled |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` from `modules/srvctl/commands/update-install.sh:83` | Calls `install_named` |
| `hooks/version.sh` | `sc version` | `msg_version_installed bind` — prints installed bind version or "bind not installed" |

## Libs
| function | file | notes |
|---|---|---|
| `namedcfg` | `libs/bashlib.sh:3-11` | Runs `/bin/node $SC_INSTALL_DIR/modules/named/named.js`; `exif "BIND/NAMED-ERROR"` on nonzero exit. Only called from this module's regenerate hook |
| `install_named` | `libs/install.sh:3-40` | Sources `installnamedlib.sh` for heredoc procedures; installs `bind bind-utils` and `ntp` if missing; enables/starts `ntpd`; `mkdir -p /var/srvctl3/named`; writes `/etc/named.conf`; truncates `/var/named/named.conf.local`; rsyncs bind sample configs; creates `/var/named/{dynamic,srvctl}`; chowns `/var/named` to `named:named`, chmod 750 on `srvctl`; `add_service named`; `firewalld_add_service dns` |
| `install_dyndns` | `libs/install.sh:42-99` | DEAD CODE: `ntc "dyndns implementation not ready"; return` at line 45-46 before any work; the remainder (dyndns-server.service, HMAC-MD5 key gen, key conf) is unreachable |
| `restart_named` | `libs/systemdlib.sh:3-19` | `systemctl restart named.service`; if not active afterwards: run `named-checkconf`, `err "named restart FAILED!"`, print `systemctl status` |
| procedures | `installnamedlib.sh` | `procedure_write_dyndns_server_service` (dormant), `procedure_write_etc_named_conf`, `procedure_write_named_srvctl_include_key_conf` (dormant); sourced on demand by `install_named`, not via module lib auto-load |
| `named.js` | module root | The generator (see Purpose). Uses `lablib.js` (`msg`/`ntc`/`err`) and `modules/datastore/lib.js` (`.hosts`) |
| `apps/dyndns-server.js`, `apps/dyndns-update.sh` | dormant | HTTPS POST server on port 855, auth via `/var/dyndns/<host>.auth` file compare, then `nsupdate` of an A record. Never installed in current code path |

## Config & templates
No `conf/` directory. Templates are inline heredocs in `installnamedlib.sh`:
- `/etc/named.conf` (`installnamedlib.sh:30-72`): trusted ACL `10.0.0.0/8; localhost; localnets`, listen on any:53 (v4+v6), `recursion yes` restricted to trusted, `dnssec-validation yes`, includes `/etc/named.rfc1912.zones`, `/etc/named.root.key`, **`/var/named/d250.conf`** (hard-coded, see Bugs), `/var/named/srvctl.conf`.
- `/etc/systemd/system/dyndns-server.service` (`installnamedlib.sh:10-26`, dormant).
- `/var/named/srvctl-include-key.conf` (`installnamedlib.sh:78-84`, dormant, hmac-md5 TSIG key).

## State touched
- Host files written: `/etc/named.conf`, `/var/named/named.conf.local` (truncated to header), `/etc/named.rfc1912.zones` + `/var/named/*` (rsync from bind samples), `/var/named/srvctl.conf`, `/var/named/srvctl/<domain>.zone` (master), `/var/srvctl3/named/<host>.json` (peer cache). Dormant: `/var/dyndns/*`, `/var/named/keys/*`, `/var/named/srvctl-include-key.conf`.
- Read: `/etc/srvctl/clusters.json`, `/var/srvctl3/datastore/containers.json`, `/var/srvctl3/named/<host>.json`.
- systemd units: `named.service` (enable+restart), `ntpd.service` (enable+start); dormant `dyndns-server.service`.
- Firewall: `firewalld_add_service dns` (53).
- Network: outbound HTTPS GET to every cluster host with a `host_ip`: `https://<host_ip>:443/.well-known/srvctl/datastore/containers.json` (`rejectUnauthorized: false`), served by `modules/datastore/apps/datastore-server.js` behind the haproxy ACL (`modules/haproxy/haproxy.js:151`). Dormant dyndns listens on TCP 855.
- Datastore: writes container key `override_in_a_ip`; reads host keys `dns_server`, `host_ip`, `host_ipv6`; reads container keys `use_host_ip`, `override_in_a_ip`, `spf_record`, `use_gsuite`, `use_mailchimp`, `use_mlsend`, `use_dmarc`, `dns_records[]` (`name/ttl/class/type/priority/data`), `aliases[]`, `google-site-verification`, `facebook-domain-verification`, `dkim-{custom,default,mail,google,mlsend}-domainkey`, plus `mail.<domain>` container's `dkim-mail-domainkey`.

## Dependencies
- Core helpers: `msg`, `ntc`, `err`, `exif`, `run`, `run_hook`, `debug` (lablib.sh/commonlib.sh); `lablib.js` `msg/ntc/err` (note: JS `err` prints to stdout).
- Modules assumed: **datastore** (`lib.js`, bash `get`/`put`, datastore-server publishing containers.json), **haproxy** (`regenerate_haproxy_conf`, routing of `/.well-known/srvctl/datastore/`), **containers** (`hs_only`, host-conf.js providing `SC_DNS_SERVER`), **srvctl** (`sc_install`, `add_service`, `msg_version_installed`, `sudomize`, `argument`), **firewalld** (`firewalld_add_service`), **certificates/letsencrypt** (provide the `regenerate_certificates` hook that `override-in-address` triggers).
- Env: `SC_COMPANY_DOMAIN` (CDN for NS/SOA names), `SC_INSTALL_DIR`, `SRVCTL`, `SC_UID0`.
- External binaries: `node`, `named`/`named-checkconf` (bind), `rsync`, `systemctl`, `dnf`, `ntpd`; dormant: `dnssec-keygen`, `nsupdate`.

## Bugs & smells
- **HIGH** `commands/override-in-address.sh:26` — `[[ $SC_UID0 ]]` tests string non-emptiness, but `SC_UID0` is always the literal `true` or `false` (`init.sh:129-131`), so the condition is always true and the denial branch at lines 31-33 (`err "$SC_USER has no access to $C"`) is unreachable. Any non-owner user proceeds to the `put`; only datastore file permissions stop the write. Intended test is `if $SC_UID0` (the pattern used at `commonlib.sh:219`).
- **HIGH (latent, fresh installs)** `installnamedlib.sh:70` — generated `/etc/named.conf` contains hard-coded `include "/var/named/d250.conf";`, a company-specific file nothing in the repo creates. On any deployment where it is absent, `named` fails to load its configuration entirely (DNS down after install + restart_named).
- **HIGH (dormant code)** `apps/dyndns-server.js:80` — `exec("/bin/bash " + __dirname + "/dyndns-update.sh " + dyndnshost)` with `dyndnshost = request.url.substring(1)` (line 48) is shell command injection; also path traversal at line 64 (`fs.readFile("/var/dyndns/" + dyndnshost + ".auth")`) and line 73. Currently unreachable because `install_dyndns` is disabled, but must not be revived as-is.
- **MEDIUM** `named.js:382-394` with `named.js:57-61` — the `process.on("exit")` handler calls `exit()` which sets `process.exitCode = 0` *after* `return_error()`'s `process.exit(111)` (Node re-reads `process.exitCode` after 'exit' listeners run). Concrete case: no master with `host_ip` triggers `return_error` at `named.js:101-102`, then the exit handler still runs `make_conf()`, writes a broken `/var/named/srvctl.conf` (slave zones with empty `masters {};`) and resets the exit code to 0 — `exif "BIND/NAMED-ERROR"` (`libs/bashlib.sh:10`) passes and `restart_named` restarts BIND on a config that fails to load. Related: if `clusters.json` is unreadable (`named.js:84-88`), the exit handler throws `TypeError` on undefined `clusters` (`named.js:309`) producing an uncaught exception during exit instead of the clean `DATA-ERROR` path.
- **MEDIUM** `libs/install.sh:11-14` — installs and enables `ntp`/`ntpd`, which is retired on current Fedora (chrony replaced it); `sc_install ntp` and `systemctl enable ntpd` fail with noisy errors and no time sync gets configured by this module. Similarly `installnamedlib.sh:51` (`bindkeys-file "/etc/named.iscdlv.key"`) is an obsolete BIND option and `libs/install.sh:28-29` rsyncs `/usr/share/doc/bind/sample/...`, which recent bind packages no longer ship — failures are unchecked (no `run`/`exif`).
- **MEDIUM** `named.js:322-330` — peer fetch has no effective timeout: `new https.Agent({ timeout: 1000 })` only sets a socket timeout with no `'timeout'` listener and the request is never destroyed, so one unresponsive peer can stall `named.js` (and thus `sc regenerate`) indefinitely.
- **MEDIUM (dormant)** `installnamedlib.sh:18` — dyndns-server.service `ExecStart` points at `modules/named/hs-apps/dyndns-server.js`; the file actually lives at `modules/named/apps/dyndns-server.js`, so the unit could never start.
- **LOW** `commands/override-in-address.sh:29-33` — despite the help text ("Override the IN A ... in named DNS server zone file", line 4), the command never runs `namedcfg`/`restart_named`; the zone change only materializes at the next full `regenerate`.
- **LOW (dormant)** `libs/install.sh:50,96` — `$CDN` is never defined in any bash scope (only in named.js as a JS const), so the cert-existence test checks `/etc/srvctl/cert//.key`; and line 77 chowns `/var/dyndns/srvctl.private`, a path never created (keys are written under `/var/named/keys`, lines 74-75). Also `dnssec-keygen -a HMAC-MD5` (line 73) is unsupported by modern BIND (tsig-keygen replaced it).
- **LOW** `named.js:107` — `r = br;` in `splitstring` creates an implicit global (no `var`); works only because the script is non-strict. `libs/systemdlib.sh:7` similarly leaks global `test`.
- **LOW** `named.js:252-253` — for a `use_gsuite` domain missing `dkim-google-domainkey`, the DMARC record is silently omitted (only an `err` line, which lablib.js prints to stdout); mail policy weakens without failing the run.

## Polish risks
- Exit-code protocol of `named.js`: initial 99, success 0, `DATA-ERROR` 111 with `console.error("DATA-ERROR:", ...)` prefix (`named.js:43,50-61`); `exif "BIND/NAMED-ERROR"` message (`libs/bashlib.sh:10`).
- Paths that BIND config and peers depend on: `/var/named/srvctl.conf` (`named.js:387`, included by `installnamedlib.sh:71`), master zone files `/var/named/srvctl/<domain>.zone` (`named.js:282-283`, aliases share the primary's zone file, `named.js:286`), slave zone files `<domain>.slave.zone` / `<alias>.slave.zone` (`named.js:296-299`), peer cache `/var/srvctl3/named/<host>.json` (`named.js:263,358`), local source `/var/srvctl3/datastore/containers.json` (`named.js:264`), clusters source `/etc/srvctl/clusters.json` (`named.js:38`).
- Fetch endpoint must stay `https://<host_ip>:443/.well-known/srvctl/datastore/containers.json` with self-signed certs accepted (`named.js:322-330`) — it must match `modules/datastore/apps/datastore-server.js:8` and the haproxy ACL.
- Zone-content semantics visible in public DNS (`named.js:117-257`): `$TTL 1D`; SOA serial = unix epoch seconds; NS `ns1.`/`ns2.<SC_COMPANY_DOMAIN>.`; wildcard `*` and `@` A records; `override_in_a_ip` with the `"none"` sentinel (`named.js:135,157-163`); SPF assembly order and includes (`_spf.google.com`, `servers.mcsv.net`, `_spf.mlsend.com`, `~all`); gsuite MX set; default `@ IN MX 10 mail` suppressed by custom MX or gsuite (`named.js:165-197`); DKIM selectors `default`, `mail`, `google`, `ml`, mailchimp `k1-k3` CNAMEs; 33-char DKIM key splitting (`named.js:106`); DMARC `p=reject` record and its suppression rules (`named.js:248-255`).
- Datastore key names (fleet data uses them): `override_in_a_ip`, `use_host_ip`, `spf_record`, `use_gsuite`, `use_mailchimp`, `use_mlsend`, `use_dmarc`, `dns_records`, `aliases`, `google-site-verification`, `facebook-domain-verification`, `dkim-*-domainkey`, host `dns_server`/`host_ip`/`host_ipv6`.
- Skip rules: domain equal to `SC_COMPANY_DOMAIN` and names without a dot are excluded (`named.js:278-279,292-293`); duplicate domains resolved first-seen-wins in clusters.json iteration order (`named.js:280,294`).
- Activation contract: enabled only when `SC_DNS_SERVER` ∈ {`master`,`slave`} (`module-condition.sh:3`); master/slave role additionally read per-host from datastore (`named.js:70`) and clusters.json (`named.js:92-99`).
- Command surface: name `override-in-address`, syntax `VE [none|ip]`, hint/help lines (`commands/override-in-address.sh:3-5`), `exit 4` when `$SRVCTL` unset (line 10), `msg "Container $ARG - $user ($reseller) - $OPA"` (line 19).
- `/etc/named.conf` is overwritten on every `update-install` (`installnamedlib.sh:30`); existing production masters rely on the `/var/named/d250.conf` include being present — removing it breaks those hosts, keeping it breaks fresh installs; needs a migration decision, not a silent change.
- Function names `namedcfg`, `restart_named`, `install_named` are the hook-facing API.

## v4 notes
- Rewrite `named.js` as `.mjs` with `async`/`Promise.all` peer fetches (real timeouts, abort controllers) instead of the "process data on the exit event" trick (`named.js:372-394`); make error/exit paths explicit so the exit-code-masking bug class disappears.
- The master and slave branches of `get_conf` (`named.js:276-301`) are near-duplicates — unify with a role parameter. The five `dkim-*-domainkey` blocks (`named.js:212-231`) are one loop over a selector map.
- Zone building is pure string assembly — extract a testable `renderZone(container, host)` and snapshot-test against current output before porting.
- Decide the dyndns subsystem's fate: it is dead code (`libs/install.sh:45-46`), has a wrong ExecStart path, hard-coded uid 103 (`apps/dyndns-server.js:110`), HMAC-MD5, and command injection. Either delete it in v4 or rebuild on `tsig-keygen` + input validation.
- `installnamedlib.sh` (source-on-demand heredocs) can fold into the module lib or become template files under `conf/`, matching other modules.
- Parameterize the `d250.conf` include (emit only if the file exists at generation time) and drop `ntp` in favor of chrony checks.
- Skip fetching the local host's own containers.json over HTTPS (`named.js:374-380` fetches all hosts including self, while `get_conf` reads the local datastore file directly, `named.js:264`).
- Garbage-collect stale `/var/named/srvctl/*.zone` files for removed domains.
- Overlap check: the separate `dns` module only does `dns_scan` (resolver verification) and is orthogonal; still, v4 could group both under one DNS domain area. `override-in-address` is really a reverse-proxy-wide setting (its own comment, `commands/override-in-address.sh:36`) — consider relocating it to haproxy/containers and having datastore writes trigger DNS regeneration on masters.
