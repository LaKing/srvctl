# Module haproxy — v3 fact sheet (commit 988c38c)

## Purpose
Manages HAProxy as the farm's HTTP/HTTPS reverse proxy on container hosts. Generates the full
`/etc/haproxy/haproxy.cfg` from the datastore (one frontend per protocol/port, one backend per
container), loads TLS certificates into `/var/haproxy`, installs haproxy + rsyslog logging, and
exposes two user commands (`http-redirect`, `https-redirect`) that store per-container redirect
rules in the datastore and re-render/reload the proxy.

## Activation
`modules/haproxy/module-condition.sh` simply sources
`modules/containers/module-condition.sh` — haproxy is enabled exactly when the containers
module is: not on `localhost.localdomain`, not inside an nspawn/lxc container, and the host
is listed in `/etc/srvctl/hosts.json` (with `$SC_HOSTNET` or `/etc/srvctl/data` present), or
during `update-install <arg>`. Result cached as `SC_USE_HAPROXY` in `modules.conf`.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| `http-redirect VE [none\|https\|URL]` | Redirect http traffic of a given VE to a given URL or protocol | `hs_only`; requires container arg; reads container `user`/`reseller` from datastore; owner/reseller gets `sudomize`d to root; then stores `$OPA` under container key `http-redirect` and re-renders | `put container C http-redirect OPA`; `run_hook regenerate_certificates`; `regenerate_haproxy_conf` (writes `/etc/haproxy/haproxy.cfg`, reloads haproxy). Root gate at commands/http-redirect.sh:29 is broken (see Bugs) |
| `https-redirect VE [none\|http\|URL]` | Redirect https traffic of a given VE to a given URL or protocol | Same flow as above but keyed `https-redirect`; root gate is `[[ $USER == root ]]` (commands/https-redirect.sh:28) | `put container C https-redirect OPA`; `run_hook regenerate_certificates`; `regenerate_haproxy_conf` |

Both commands print `msg "Container $ARG - $container_user ($container_reseller) - $OPA"` and
on (intended) denial `err "$SC_USER has no access to <VE>"` then `exit` (code 0!).
Empty/`none` OPA removes the key; note an *absent* `http-redirect` key means "default redirect
http→https" in the generator (haproxy.js:275), while `none` means "serve http directly".

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/regenerate.sh` | `sc regenerate` (via containers/commands/regenerate.sh:30 `run_hook regenerate`; hourly via `/etc/cron.hourly/srvctl-regenerate.sh` with ARG=`#cron.hourly`) | `run_hook regenerate_certificates` (certificates module: `apply_wildcard_certificates`), then `regenerate_haproxy_conf` |
| `hooks/update-install-host.sh` | `sc update-install` on hosts (srvctl/commands/update-install.sh:83 `run_hooks update-install-host`) | `sc_install haproxy socat rsyslog`; `mkdir -p /var/haproxy`; writes `/etc/rsyslog.d/haproxy.conf` (local2 → `/var/log/haproxy.log`); **overwrites `/etc/rsyslog.conf` wholesale** (UDP 514 syslog input enabled); enables+restarts rsyslog; imports `/etc/srvctl/cert/<d>/<d>.pem` → `/var/haproxy/<d>.pem` |
| `hooks/diagnose.sh` | `sc diagnose` | No-op: entire body commented out (socat stats-socket queries kept as comments) |

## Libs
| function | file | notes |
|---|---|---|
| `haproxycfg` | libs/bashlib.sh:3 | Runs `/bin/node modules/haproxy/haproxy.js` capturing stdout+stderr; `exif "HAPROXY-ERROR cfg …"` on failure; echoes node output. Internal to module |
| `load_certificate_folder_files DIR` | libs/proxylib.sh:3 | For each `DIR/*.pem`: `check_pem` (certificates module — validates and *deletes* near-expired certs), then `cp -u` into `/var/haproxy/`. Internal |
| `regenerate_haproxy_conf` | libs/proxylib.sh:20 | mkdirs `$SC_DATASTORE_DIR/cert`, `$SC_DATASTORE_DIR/pki-validation`, `/var/haproxy`, `/etc/srvctl/cert`; loads certs from `/var/srvctl3/datastore/cert` (hardcoded) and `/etc/srvctl/cert/*`; removes `/var/haproxy/ca-bundle.pem`; `haproxycfg`; `reload_haproxy` unless `$ARG == "#cron.hourly"`. **Used cross-module** by `modules/named/commands/override-in-address.sh:30` |
| `restart_haproxy` | libs/systemdlib.sh:3 | `systemctl restart haproxy.service`; if inactive afterwards runs `haproxy -c -f /etc/haproxy/haproxy.cfg`, `err "HAproxy restart FAILED!"`, `systemctl status --no-pager`; always `run 'sleep 1'` |
| `reload_haproxy` | libs/systemdlib.sh:23 | `systemctl reload`; sleep 1; if unit inactive: `err "HAproxy INACTIVE"`, status, fall back to `restart_haproxy`; sleep 1 |

## Config & templates
- `haproxy.cfg` (module root): stock Fedora example config; referenced by nothing in the repo — dead file, never installed.
- `haproxy.js` (module root, 529 lines): the real "template" — Node script that renders and writes `/etc/haproxy/haproxy.cfg` directly. Reads `modules/datastore/lib.js` (containers/hosts/users) and env `SRVCTL, SC_UID0, SC_COMPANY_DOMAIN, SC_USE_CODEPAD`. Generated config: global/defaults (maxconn 50000, 5m client/server timeouts, gzip compression, optional errorfiles from `/var/www/html/*.http`); `frontend http *:80`, `frontend https *:443 ssl crt /var/haproxy alpn h2,http/1.1`; extra frontends+backends for ports 9200 (ssl fe, plain be), 8080 (plain), 8443 (ssl), and 9000/9001 (ssl) when `SC_USE_CODEPAD=true`; per-container backends `http:<ve>` → `<ve>:<http_port|80>` and `https:<ve>` → `<ve>:<https_port|443> ssl verify none alpn h2,http/1.1`; well-known ACLs routing `/.well-known/acme-challenge/`→127.0.0.1:1028, `/.well-known/autoconfig/mail/`→127.0.0.1:1029, `/.well-known/srvctl/datastore/` and `/.well-known/pki-validation/`→127.0.0.1:1030; `backend default` → `localhost:1282` (modules/default/server.js).
- No `conf/` directory.

## State touched
- Host files: `/etc/haproxy/haproxy.cfg` (written by haproxy.js:518), `/var/haproxy/*.pem` (cert cache), `/etc/rsyslog.conf` + `/etc/rsyslog.d/haproxy.conf` (update-install-host.sh:13-98), `/var/log/haproxy.log` (via rsyslog local2), `$SC_DATASTORE_DIR/cert`, `$SC_DATASTORE_DIR/pki-validation` (mkdir only).
- systemd units: `haproxy.service` (reload/restart/status), `rsyslog.service` (enable/restart).
- Datastore keys (per container): reads `user`, `reseller`; writes `http-redirect`, `https-redirect`; haproxy.js additionally reads `aliases`, `altnames`, `static`, `proxy_ports`, `http_port`, `https_port`; containers named `mail.*` are excluded from proxying (haproxy.js:70).
- Network: binds *:80, *:443, *:8080, *:8443, *:9200 (+9000/9001 with codepad); backends reach containers by hostname; syslog UDP 514 opened in rsyslog.

## Dependencies
- Core helpers: `msg ntc err run exif eyif` (lablib.sh), `run_hook` (commonlib.sh), `$SRVCTL $ARG $OPA $SC_USER $SC_UID0 $SC_INSTALL_DIR $SC_DATASTORE_DIR`.
- Other modules (hard): **containers** (`hs_only`, module condition), **srvctl** (`argument`, `sudomize`, `sc_install`), **datastore** (`get`/`put` bash wrappers, `lib.js`, `main.js`), **certificates** (`check_pem` in proxylib.sh:9 — marked "## unused" in its own lib but used here; `regenerate_certificates` hook). Soft consumers: **named**, **letsencrypt** (port 1028 server), **mozilla** (1029), **datastore server** (1030), **default** (1282), **codepad** (`SC_USE_CODEPAD`).
- External binaries: `haproxy`, `systemctl`, `node` (`/bin/node`), `rsyslog`, `socat` (installed but only used by commented-out diagnose), `dnf` (via sc_install), `openssl` (via check_pem).

## Bugs & smells
- **high** commands/http-redirect.sh:29 — `[[ $SC_UID0 ]]` tests string non-emptiness, but `SC_UID0` is always the string `true` or `false` (init.sh:129-131), so the gate always passes and the `err "$SC_USER has no access to $C"` branch (line 35) is unreachable. Any srvctl user who is not owner/reseller (so not `sudomize`d) proceeds into the privileged path and attempts `put container … http-redirect …` as themselves — denial today depends solely on datastore file permissions (commonlib.sh:489-492) and yields a misleading `DATASTORE-ERROR` exit instead of an access-denied message; any permission drift makes it an unauthorized config write plus proxy regeneration. (Same defect pattern exists in modules/named/commands/override-in-address.sh:26.)
- **medium** libs/proxylib.sh:9 → modules/certificates/libs/domaincertlib.sh:34 — `check_pem` does `rm -rf "$pem"` on any certificate expiring within 7 days. `regenerate_haproxy_conf` runs it over `/var/srvctl3/datastore/cert` and every `/etc/srvctl/cert/*` dir on every regenerate (hourly via cron), silently deleting admin-managed source certificates that are still valid for up to 7 days, while the previously copied (eventually expired) `/var/haproxy/*.pem` copy is never removed and keeps being served.
- **medium** libs/systemdlib.sh:25-28 — `reload_haproxy` has no else branch: if `systemctl reload haproxy` fails while the old process stays active (typical for an invalid newly-generated config), the function prints `haproxy.service active` and returns success; the new config is silently never applied and no syntax check runs (the "haproxy syntax check" comment at line 35 has no command).
- **low** libs/proxylib.sh:36 — cert source path `/var/srvctl3/datastore/cert` is hardcoded, ignoring `SC_DATASTORE_RW_DIR` (default set in modules/datastore/hooks/pre-init.sh:9); also line 26 mkdirs `$SC_DATASTORE_DIR/cert`, which may resolve to the read-only gluster dir (modules/datastore/libs/datalib.sh:113), an inconsistent pair.
- **low** commands/https-redirect.sh:28 vs commands/http-redirect.sh:29 — twin commands use different root gates (`[[ $USER == root ]]` vs broken `[[ $SC_UID0 ]]`); https-redirect happens to work, http-redirect does not; also `exit` without code at http-redirect.sh:36 / https-redirect.sh:35 returns 0 on the "no access" path.
- **low** haproxy.js:93 — `ddn()` appends `SC_COMPANY_DOMAIN` from env without a guard; if unset, generated config contains ACLs for `<host>.undefined` hostnames (garbage but syntactically valid).
- smell: hooks/diagnose.sh is entirely commented out (dead hook still sourced); module-root `haproxy.cfg` is dead example code; haproxy.js has many unused imports/vars (`ntc, run, rok, get, hosts, users, resellers, CMD, HOSTNAME, SRVCTL, SC_UID0, localhost, out, return_value`) and undeclared loop variable `j` (implicit global, haproxy.js:268,294,331,353).

## Polish risks
A rewrite must preserve, byte-for-byte where marked:
- Generated file path `/etc/haproxy/haproxy.cfg` (haproxy.js:518) and its structure: frontend names `http`/`https`/`port<N>` (haproxy.js:257,320,374), backend names `http:<ve>`, `https:<ve>`, `port<N>:<ve>`, `default` (haproxy.js:419,439,463,512) — these names appear in haproxy logs/stats and any tooling parsing them.
- Semantics of datastore keys `http-redirect`/`https-redirect`: absent key ⇒ default 301 http→https (haproxy.js:275); `none` ⇒ serve directly; `https`/`http` keyword ⇒ protocol flip; anything else used verbatim as `redirect prefix <value>` (haproxy.js:277-279,336-339). `www.<domain>` → apex 301 always added (haproxy.js:265,328,174-177); alias redirects add `Cache-Control "max-age=86400"` on 301 (haproxy.js:173).
- Redirect exception suffix `" !.well-known-acl"` (haproxy.js:144) and ACL names `.well-known-acl`, `letsencrypt-acl`, `thunderbird-acl`, `srvctl3data-acl`, `pki-validations-acl` with backend targets 127.0.0.1:1028/1029/1030 and `backend default → localhost:1282` (haproxy.js:148-152,424-429,512-513).
- Container set rules: `mail.*` excluded (haproxy.js:70); ordering by descending domain-segment count (haproxy.js:69-79) — first-match ACL semantics depend on it; `static` containers get no use_backend ACLs but keep backends/redirects (haproxy.js:290-291); `<host>-<segments>.<SC_COMPANY_DOMAIN>` alias ACLs via `ddn()` (haproxy.js:92-94); wildcard-subdomain ACLs `-m end .<domain>` (haproxy.js:114-127); ports 9000/9001 gated on `SC_USE_CODEPAD=true` env plus `proxy_ports` containing the port or `-devel` in the VE name (haproxy.js:387-389,459-461); fixed extra ports 9200 (ssl fe/plain be), 8080, 8443 (haproxy.js:490-509); cert dir literal `/var/haproxy` in bind lines (haproxy.js:321,377-378).
- Certificate flow: certs cached as `/var/haproxy/<domain>.pem`; `cp -u` only (never prunes stale certs except `ca-bundle.pem`, proxylib.sh:45); sources `/var/srvctl3/datastore/cert` and `/etc/srvctl/cert/*` (proxylib.sh:36-41); update-install imports `/etc/srvctl/cert/<d>/<d>.pem` (update-install-host.sh:107-118).
- `$ARG == "#cron.hourly"` skips reload with msg `Skipping reload for automatic regeneration #cron.hourly` (proxylib.sh:51-56) — cron regenerates config hourly but intentionally never reloads haproxy.
- Exit codes: `exit 4` when `$SRVCTL` unset (commands/*.sh:13); `exit 44` from `hs_only`; `exit 32` from `argument`; haproxy.js exit 0 success / 111 write error (haproxy.js:48) / 99 abnormal default (haproxy.js:31), enforced by `exif` in `haproxycfg` (bashlib.sh:9).
- User-visible strings: `Container $ARG - $container_user ($container_reseller) - $OPA`; `$SC_USER has no access to <VE>`; `Regenerate haproxy configs.` (proxylib.sh:29); `wrote haproxy conf` (haproxy.js:520, emitted through haproxycfg's echo); `Using only static config for <ve>` (haproxy.js:290); `reloaded haproxy.service`, `haproxy.service active`, `HAproxy INACTIVE`, `restarted haproxy.service`, `HAproxy restart FAILED!` (systemdlib.sh); `Installing HAproxy as the reverse proxy`, `Import Haproxy certificate <d>` (update-install-host.sh:5,114); help headers `## @@@ http-redirect VE [none|https|URL]` / `## @@@ https-redirect VE [none|http|URL]`.
- rsyslog contract: local2 → `/var/log/haproxy.log`, UDP 514 input enabled, `/etc/rsyslog.conf` replaced (update-install-host.sh:13-98).
- Global config values that ops may depend on: maxconn 4096/50000, `timeout client/server 5m`, `ssl-server-verify none`, `tune.ssl.default-dh-param 2048`, compression types, errorfiles from `/var/www/html/<code>.http` only when present (haproxy.js:181-247).

## v4 notes
- haproxy.js is 80% string concatenation — natural .mjs port: a pure `renderConfig(datastore, opts) -> string` plus a thin writer; make it testable by separating render from `fs.writeFile` and dropping the implicit env coupling (SC_COMPANY_DOMAIN, SC_USE_CODEPAD as explicit params).
- The acl/subacl/aacl trio (haproxy.js:98-142) is one function with three call shapes; redirect generation is duplicated between http and https frontends — unify.
- `http-redirect.sh` and `https-redirect.sh` are copy-paste twins (also of named/override-in-address.sh) differing in one datastore key; v4 should have one `set-container-key + regenerate` primitive with a real authorization helper (fixing the `[[ $SC_UID0 ]]` class of bug once).
- Port-frontend gating logic (codepad 9000/9001, 9200, 8080, 8443) is hardcoded three times (frontend, subdomain loop, backend) — should be data-driven (`proxy_ports` in datastore) and hook/module-extensible (the "TODO, implement as hook?" at haproxy.js:481).
- Cert loading duplicates the certificates module's concerns; v4 should give cert sync (including pruning stale /var/haproxy copies, and *not* deleting sources) to the certificates unit, and have haproxy only consume `/var/haproxy`.
- Reload strategy deserves an explicit contract: validate (`haproxy -c`) before reload, report reload failure, and reconsider the hourly no-reload rule (renewed certs currently wait for a manual action to be served).
- Dead weight to drop: module-root `haproxy.cfg`, commented-out diagnose.sh (or resurrect as real `show stat` diagnostics via socat, which is installed for exactly that).
