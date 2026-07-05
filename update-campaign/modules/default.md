# module default — v3 fact sheet (commit 988c38c)

## Purpose
Provides the "default page server": a tiny Node.js HTTP daemon (`default-server.service`, port 1282) that answers every request with HTTP 404 and the branded error page `/var/www/html/404.html`. It is the catch-all backend for the haproxy module — haproxy frontends end with `default_backend default` (modules/haproxy/haproxy.js:311,366,410) whose only server is `localhost:1282` (modules/haproxy/haproxy.js:512-513). Any HTTP(S) request whose Host does not match a hosted site lands here.

## Activation
`module-condition.sh` (modules/default/module-condition.sh:3) simply sources the containers module's condition, so the default module is enabled exactly when the containers module is:
- false on `localhost.localdomain` hostname (containers/module-condition.sh:3-7)
- requires `$SC_HOSTNET` set or `/etc/srvctl/data` present (containers/module-condition.sh:9)
- false inside a container (`systemd-detect-virt -c` = systemd-nspawn or lxc, containers/module-condition.sh:12-19)
- true if `$HOSTNAME` appears in `/etc/srvctl/hosts.json` (containers/module-condition.sh:21-25)
- true during `sc update-install <ARG>` bootstrap (containers/module-condition.sh:28-32)
Condition is evaluated in a subshell (`trtm="$(source ...)"`, commonlib.sh:436) and cached as `SC_USE_DEFAULT` in `/var/local/srvctl/modules.conf`.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | (module has no `commands/` directory) | - |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| hooks/update-install-host.sh | `update-install-host` — sourced by `run_hooks update-install-host` from `sc update-install HOSTNAME` on hosts (modules/srvctl/commands/update-install.sh:83), between `pre-` and `post-` phases, in alphabetical module order (srvctl.sh:72-75) | Heredoc-writes `/etc/systemd/system/default-server.service` (lines 3-17: `ExecStart=/bin/node $SC_INSTALL_DIR/modules/default/server.js`, `User=nobody`, `Group=nobody`, `Restart=always`), then `run systemctl daemon-reload`, `enable`, `start`, `status --no-pager` (lines 19-23) |

## Libs
- (no `libs/` directory)
- `server.js` is the daemon payload, executed by systemd, never sourced by bash. Reads `/var/www/html/404.html` at startup (server.js:6), logs `host url user-agent x-forwarded-for` per request (server.js:11), always responds `404 text/html` with the file content (server.js:14-16), listens on port 1282 on all interfaces (server.js:20), prints `srvctl default-server started` (server.js:21). Nothing else in the tree imports it.

## Config & templates
- No `conf/` directory. The systemd unit is generated inline by the hook (see above); `$SC_INSTALL_DIR` is expanded at generation time.

## State touched
- Host file: `/etc/systemd/system/default-server.service` (created/overwritten on every `update-install`)
- systemd: `daemon-reload`; unit `default-server.service` enabled + started; never stopped/disabled/removed by any code path
- Reads at runtime: `/var/www/html/404.html` (written by the branding module: modules/branding/hooks/update-install-host.sh:7 via `setup_varwwwhtml_error 404`)
- Network: TCP 1282 bound on 0.0.0.0; consumed by haproxy at `localhost:1282`; port 1282 is NOT opened by the firewalld module (only named services like http/https are)
- Logs: request lines and startup message to journald (unit `default-server`)

## Dependencies
- Core helpers: `run` (lablib.sh:93 — echoes command, executes, `eyif`-warns on failure; note lablib.sh:108 skips the warning entirely whenever `$1 == systemctl`, so failed enable/start goes unnoticed)
- Hook dispatch: `run_hook`/`run_hooks` (commonlib.sh:85-114), gated on `SC_USE_DEFAULT=true`
- Other modules: **containers** (condition is literally sourced from it); **branding** (must have produced `/var/www/html/404.html`; runs first only because "branding" < "default" in the alphabetical `SC_MODULES` glob, srvctl.sh:72-75); **haproxy** (the only consumer of port 1282)
- External binaries: `node` at `/bin/node` (installed by update-install.sh:43 before hooks run), `systemctl`, `cat`

## Bugs & smells
- **medium** modules/default/server.js:6 — unguarded `fs.readFileSync('/var/www/html/404.html')` at startup: if the file is absent (branding hook never ran on this host, or the file was deleted — e.g. by cleanup in `/var/www/html`), the process throws before `listen()`; with `Restart=always` and no `RestartSec` (hooks/update-install-host.sh:13) systemd restarts every 100 ms, hits the start-limit within ~1 s, and the unit lands in permanent `failed` state — every unmatched-Host request on the farm then gets haproxy's raw 503 instead of the branded 404.
- **low** modules/default/server.js:20 — `server.listen(1282)` binds all interfaces instead of 127.0.0.1, although the only legitimate client is haproxy on localhost; protection relies entirely on firewalld not opening 1282, and the port is reachable over any permissive zone/interface (e.g. the 10.x OpenVPN mesh).
- **low** modules/default/hooks/update-install-host.sh:22 — `systemctl start` (not `restart`): re-running `sc update-install` after a srvctl code update leaves an already-running daemon executing the old `server.js` until reboot (update-install does end with "please reboot", which masks this in practice).
- **low** modules/default/hooks/update-install-host.sh:21-23 — failures of `systemctl enable/start` are silently swallowed because `run` suppresses `eyif` for any command whose first word is `systemctl` (lablib.sh:108); a broken unit install produces no error in the update log.
- **smell** modules/default/server.js:6 — `html404` is an implicit global (no `var`/`let`/`const`); works only in sloppy mode, would `ReferenceError` under `"use strict"`/ESM.
- **smell** (no file) — no code path ever stops, disables, or removes `default-server.service` when the module or srvctl itself is removed; the unit with a baked-in `$SC_INSTALL_DIR` path outlives its source.

## Polish risks
A rewrite must preserve, byte-for-byte where noted:
- Port **1282** — hardcoded on the consumer side at modules/haproxy/haproxy.js:513 (`server default-server localhost:1282`).
- Unit name and path `/etc/systemd/system/default-server.service` (hooks/update-install-host.sh:3) — enabled state on production hosts references this exact name.
- Unit contents: `Description=srvctl default page server`, `After=network.target`, `Type=simple`, `ExecStart=/bin/node $SC_INSTALL_DIR/modules/default/server.js`, `User=nobody`, `Group=nobody`, `Restart=always`, `WantedBy=multi-user.target` (hooks/update-install-host.sh:4-16). Changing User/ExecStart alters file-permission and SELinux assumptions.
- Source of the body: `/var/www/html/404.html` exactly (server.js:6) — produced by branding's `setup_varwwwhtml_error 404 "Not found."` (modules/branding/hooks/update-install-host.sh:7); file must stay readable by user `nobody`.
- Response semantics: always status **404**, header `Content-Type: text/html`, body = the branded page (server.js:14-16) — monitoring and users of unmatched vhosts see this today.
- Journal strings: startup line `srvctl default-server started` (server.js:21) and per-request line `<host> <url> <user-agent> <x-forwarded-for>` space-separated via console.log (server.js:11) — greppable log format.
- Hook must remain at lifecycle point `update-install-host` and must not fail the surrounding `update-install` run (currently all systemctl results are non-fatal).
- Activation must stay identical to the containers module (`SC_USE_DEFAULT` mirrors `SC_USE_CONTAINERS`).
- Alphabetical ordering dependency: branding's identical hook must still run before default's so `404.html` exists when the service first starts.

## v4 notes
- `server.js` is the natural first `.mjs` candidate: ~20 lines, no bash coupling. While porting: bind `127.0.0.1`, lazy-read or embed a fallback page, add `RestartSec`, consider `DynamicUser=yes`.
- Alternative worth evaluating: drop the daemon entirely — haproxy already serves branding's `.http` errorfiles for 400/403/500/502/503/504 (haproxy.js:230-243); a static `404.http` default backend or `http-request return` directive could replace a permanently-running node process.
- The `source ../containers/module-condition.sh` pattern (shared with branding) is implicit dependency declaration; v4 module manifest should express `requires: containers` declaratively and derive ordering from it instead of relying on alphabetical globbing.
- Heredoc-generated systemd units appear in many modules; a shared `install_unit` helper (write + diff-aware daemon-reload + restart-on-change) would fix the stale-code-after-update problem farm-wide.
- The `run`/systemctl warning-suppression quirk (lablib.sh:108) affects every module; fix once in core, not per module.
