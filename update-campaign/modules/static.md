# static — v3 fact sheet (commit 988c38c)

## Purpose
Emergency/fallback static file server for the container farm: a root-run Node.js HTTP
server (`server.js`, systemd unit `static-server.service`, port **1280**) that serves
per-domain document roots from `/var/srvctl3/storage/static/<host-header>/html`. The
module also maintains that directory tree (one dir per cluster container, seeded with a
branding index.html) and optionally puts `/var/srvctl3/storage` on a replicated gluster
volume. The header comment (server.js:1–5) explains the design: files are served
on-demand over plain HTTP because the old **pound** proxy could not serve emergency
pages itself. **At this commit nothing routes traffic to port 1280** — the haproxy
`default` backend points at `localhost:1282` (the `default` module,
modules/haproxy/haproxy.js:511–513), and no other config references 1280 — so the
service is effectively orphaned (see Bugs / v4 notes).

## Activation
`modules/static/module-condition.sh` (3 lines) simply sources
`$SC_INSTALL_DIR/modules/containers/module-condition.sh`, so **static is enabled exactly
when the containers module is enabled**:
- `false` on `localhost.localdomain`;
- requires `$SC_HOSTNET` set or `/etc/srvctl/data` present;
- `false` inside a container (`systemd-detect-virt -c` = `systemd-nspawn`/`lxc`);
- `true` if `$HOSTNAME` appears in `/etc/srvctl/hosts.json`;
- also `true` during `update-install` with an argument (bootstrap path).

Result is cached as `SC_USE_STATIC=true|false` in `modules.conf` by
`test_srvctl_modules` (commonlib.sh:404–479).

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | module has no `commands/` directory | - |

(Only entry points are hooks and, when enabled, `sc exec-function
regenerate_static_server` via `run_command`'s exec-function path, commonlib.sh:123–128.)

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/init.sh` | every srvctl invocation (`run_hook init`, init.sh:182) | If `$SC_USE_GLUSTER`: `gluster_mount_data srvctl-storage /var/srvctl3/storage` (mounts the replicated volume); else `mkdir -p /var/srvctl3/storage`. Always `return 0` (masks failures). Gluster branch is dead at this commit (gluster module hard-disabled). |
| `hooks/regenerate.sh` | `run_hook regenerate` — fired by `regenerate` command (modules/containers/commands/regenerate.sh:30), `add-ve`, `add-ve-user`, `add-network-ve`, `add-codepad`, and regenlib all-hosts loop | Prints `msg "Regenerate static fileserver structure"` then calls `regenerate_static_server` (from libs). |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` during `sc update-install` (modules/srvctl/commands/update-install.sh:83) | If `$SC_USE_GLUSTER`: `gluster_configure srvctl-storage /var/srvctl3/storage` (dead at this commit). Deletes legacy `/usr/lib/systemd/system/static-server.service` (line 9, `## TODO remove after upgrade`). Writes `/etc/systemd/system/static-server.service` heredoc (`ExecStart=/bin/node $SC_INSTALL_DIR/modules/static/server.js`, `User=root`, `Restart=always`). `systemctl daemon-reload`; `cd` into the module dir (vestigial — npm installs are global); `npm install -g finalhandler` and `npm install -g serve-static` (unpinned, from the network); `mkdir -p /var/srvctl3/storage/static`; enable + start + status `static-server.service`. |

## Libs
| function | file | notes |
|---|---|---|
| `regenerate_static_server` | `libs/regenerate.sh:3–13` | For every name in `get cluster container_list` (all containers cluster-wide, not just local host): `mkdir -p /var/srvctl3/storage/static/$dir/html`; if `index.html` is missing there, call `setup_index_html "$dir (static)" ...` (branding module) to seed a placeholder page + favicon. Never overwrites an existing index.html. Used only by this module's own `hooks/regenerate.sh`; no other module calls it. |

Non-bash asset: `server.js` (44 lines) — the Node HTTP server itself. Requires
`finalhandler` and `serve-static` by absolute path `/usr/lib/node_modules/...`
(server.js:7,9). Logs every request (`host url user-agent x-forwarded-for`,
server.js:14). Host normalization: undefined Host → `d250.hu` (server.js:17–20); strips
leading `www.` and `static.` (server.js:21–22). Serves
`/var/srvctl3/storage/static/<host>/html` via serve-static; listens on 1280 (all
interfaces); prints `srvctl static-server started`.

## Config & templates
No `conf/` directory. The systemd unit is generated inline by the heredoc in
`hooks/update-install-host.sh:11–25` and installed to
`/etc/systemd/system/static-server.service`. `server.js` is executed in place from
`$SC_INSTALL_DIR/modules/static/server.js`.

## State touched
- **Host paths**: `/var/srvctl3/storage` (created or gluster-mounted at every init),
  `/var/srvctl3/storage/static/` and `/var/srvctl3/storage/static/<container>/html/`
  (+ `index.html`, `favicon.ico`); `/etc/systemd/system/static-server.service` (written),
  `/usr/lib/systemd/system/static-server.service` (removed);
  `/usr/lib/node_modules/{finalhandler,serve-static}` (npm -g).
- **Container paths**: none directly. (The containers module deletes
  `/var/srvctl3/storage/static/$C` on `remove-ve`/`destroy-ve` —
  modules/containers/commands/remove-ve.sh:63, destroy-ve.sh:47.)
- **systemd units**: `static-server.service` (daemon-reload, enable, start, status).
- **Datastore**: read-only `get cluster container_list` (keys of containers.json via
  modules/datastore/lib.js:993–1001).
- **Network**: listens TCP 1280 on all interfaces, plain HTTP, as root. Optional gluster
  volume `srvctl-storage` (dead path at this commit).

## Dependencies
- **Core helpers**: `msg`, `run` (lablib.sh:93 — echoes then executes, special-cases
  `systemctl status` exit 3), `run_hook`/`exif` machinery (commonlib.sh:85–108),
  `load_libs`.
- **Other modules**: containers (module condition is literally sourced from it, and its
  regenerate/add-ve commands fire this module's regenerate hook); datastore (`get`,
  modules/datastore/libs/bashlib.sh:20); branding (`setup_index_html`,
  modules/branding/libs/brandinglib.sh:3 — also reads `logo.svg`/`favicon.ico`);
  gluster (`gluster_mount_data`, `gluster_configure` — only if `SC_USE_GLUSTER=true`,
  currently never); srvctl module (`update-install` drives the install hook).
- **External binaries**: `/bin/node`, `npm` (network access to the npm registry at
  install time), `systemctl`, `mkdir`; the npm packages `finalhandler` and
  `serve-static` at runtime.

## Bugs & smells
- **high server.js:27–35** — the `finalhandler` `onerror` callback calls
  `res.send('error', err.statusCode)`; `res.send` does not exist on a plain
  `http.ServerResponse` (it is an Express API). finalhandler defers `onerror`, so the
  TypeError is an uncaught exception that kills the whole process. Any request that makes
  serve-static emit an error (e.g. `GET /%` — malformed percent-encoding, a 400) crashes
  the server for all clients; systemd restarts it (`Restart=always`, default 100 ms), so
  a trivial loop keeps the service permanently flapping and drops all in-flight
  transfers. Note line 33 also runs unconditionally (no `else`/`return`), so even the
  `err` falsy path would crash.
- **high server.js:37** — the document root is built from the **unvalidated Host
  header**: `serveStatic('/var/srvctl3/storage/static/' + host + '/html')`. `/` and `.`
  are legal in header values, so `Host: ../../../srv/<ve>/rootfs/var/www` escapes the
  storage tree and the root-run process serves any readable directory whose path ends in
  `/html` — e.g. other tenants' container webroots. serve-static only guards traversal
  in the URL path, not in the root it is given.
- **medium hooks/update-install-host.sh:38–39 (with server.js:42)** — the service is
  enabled and started on every host, but nothing in the codebase routes to port 1280
  (haproxy's default backend is `localhost:1282`, modules/haproxy/haproxy.js:513; the
  pound proxy mentioned in server.js:5 no longer exists). Concrete harm: a permanently
  running root HTTP server with the two vulnerabilities above, listening on all
  interfaces (reachable from containers/VPN mesh), that serves no function.
- **low server.js:21–22** — the `static.` strip reads from the original
  `req.headers.host` instead of the already-`www.`-stripped `host`:
  `www.static.example.com` → line 21 yields `static.example.com`, line 22 then computes
  `req.headers.host.substring(7)` = `tic.example.com` — wrong docroot, spurious 404.
  (A Host with an explicit `:port` is likewise never stripped and misses its docroot.)
- **low hooks/init.sh:3, hooks/update-install-host.sh:3** — `if $SC_USE_GLUSTER` with an
  *unset* variable expands to an empty command list, which bash treats as status 0, i.e.
  **true**: a stale `modules.conf` predating the gluster module would call the undefined
  `gluster_mount_data`/`gluster_configure` (exit 127, masked by `return 0` at
  hooks/init.sh:10). Harmless today only because `test_srvctl_modules` rewrites all
  variables together.
- **low server.js:7,9 + hooks/update-install-host.sh:33–34** — runtime hard-codes
  `/usr/lib/node_modules/...` while the installer relies on `npm install -g` (unpinned,
  latest-at-install-time) landing exactly there; a different npm prefix
  (`/usr/local`) or a future package major bump breaks service startup into a
  `Restart=always` crash loop.

## Polish risks
A rewrite must preserve, byte-for-byte where marked:
- Unit name and path `/etc/systemd/system/static-server.service`, with
  `ExecStart=/bin/node $SC_INSTALL_DIR/modules/static/server.js`, `Type=simple`,
  `User=root`, `Group=root`, `Restart=always`, `WantedBy=multi-user.target`
  (hooks/update-install-host.sh:11–25); removal of the legacy
  `/usr/lib/systemd/system/static-server.service` (line 9).
- Listen port **1280** (server.js:42) and plain HTTP.
- Docroot layout `/var/srvctl3/storage/static/<host>/html` (server.js:37,
  libs/regenerate.sh:7) — `remove-ve`/`destroy-ve` in the containers module hard-code
  `rm -fr /var/srvctl3/storage/static/"$C"` against this layout.
- Host normalization semantics: undefined Host → `d250.hu` (server.js:19); leading
  `www.` and `static.` prefixes stripped (server.js:21–22).
- `/var/srvctl3/storage` created (or gluster-mounted from volume `srvctl-storage`) at
  init; hook returns 0 unconditionally (hooks/init.sh:5–10).
- `regenerate_static_server` function name (libs/regenerate.sh:3 — reachable via
  `exec-function`); it must keep the "create only if `index.html` missing" rule
  (libs/regenerate.sh:8) so user-placed content is never overwritten, and the index
  title argument `"$dir (static)"` (libs/regenerate.sh:10).
- Iteration source `get cluster container_list` (libs/regenerate.sh:5) — cluster-wide
  container set, not local-only.
- Output strings: `msg "Regenerate static fileserver structure"`
  (hooks/regenerate.sh:3), `msg "regenerate static server index files"`
  (libs/regenerate.sh:4), startup line `srvctl static-server started` (server.js:43),
  per-request log format `host url user-agent x-forwarded-for` (server.js:14).
- npm packages `finalhandler` and `serve-static` installed globally and required from
  `/usr/lib/node_modules` (server.js:7,9; hooks/update-install-host.sh:33–34).
- Module activation identical to containers (module-condition.sh:3).

## v4 notes
- **First decide whether the module should exist at all**: no proxy routes to :1280 at
  this commit; either wire it back in as the haproxy emergency/default backend
  (replacing or merging with the near-identical `default` module on :1282) or drop it
  and its storage tree. `modules/default/server.js` and `modules/static/server.js` are
  siblings — one shared, parameterized static-file `.mjs` server (port, docroot
  strategy, fallback page) covers both.
- `server.js` is the natural `.mjs` candidate: modern `http` + hand-rolled safe path
  resolution (or pinned deps in a local `package.json` instead of unpinned global
  `npm install -g`), Host-header allowlisting against the datastore container list
  (fixes both high bugs at once), and structured logging.
- The systemd-unit heredoc pattern is duplicated across many modules'
  `update-install-host.sh` hooks — a shared "install unit + enable" helper (or a v4
  unit-template generator) would collapse them.
- `if $SC_USE_GLUSTER` gating and the gluster mount/configure pair are copy-pasted
  from the datastore module's hooks (datastore/hooks/init.sh, datastore/
  hooks/update-install-host.sh) — dead at this commit since gluster is hard-disabled;
  delete or centralize together with the gluster decision.
- Seeding a docroot for **every container in the cluster on every host** only made
  sense with shared gluster storage; without it, per-host local dirs for remote
  containers are noise. v4 should scope to local containers unless shared storage is
  re-enabled.
- There is no user-facing command to manage static content (root-owned dirs, manual
  upload only) — if kept, v4 wants an `add-static`/ownership story.
