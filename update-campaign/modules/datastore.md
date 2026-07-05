# datastore — v3 fact sheet (commit 988c38c)

## Purpose
The datastore module is srvctl's data layer. It stores cluster state in three JSON files
(`hosts.json`, `users.json`, `containers.json`) and exposes a small human-readable verb API
(`get`/`put`/`out`/`cfg`/`del`/`new`/`add`) as bash functions that shell out to a Node.js
program (`main.js` + `lib.js`). `lib.js` is also the central computation library: it derives
every container's UID base, bridge, gateway, interface name, IP allocation, nspawn config,
`/etc/hosts`, resolv.conf, firewall commands, port mappings, postfix relaydomains, ssh
known_hosts, and user/reseller allocation from the raw JSON. It also installs a tiny HTTP
server (`datastore-server.js`, port 1030) that serves ACME `pki-validation` files and a
public `containers.json` snapshot behind haproxy, and provides rsync-based data
synchronization between cluster hosts.

## Activation  (module-condition.sh logic — when is this module enabled)
`module-condition.sh` simply sources and re-emits `modules/containers/module-condition.sh`
(datastore is active exactly when the `containers` module is active). That condition returns
`true` when: host is not `localhost.localdomain`; `$SC_HOSTNET` is set or `/etc/srvctl/data`
exists; the host is NOT itself a systemd-nspawn/lxc container (`systemd-detect-virt -c`); and
`/etc/srvctl/hosts.json` exists and contains a `"$HOSTNAME"` key. It also returns `true` for
`update-install <ARG>`. Otherwise `false`. So the module runs on physical/cluster hosts, not
inside guests. (`modules/datastore/module-condition.sh:3`, `modules/containers/module-condition.sh:3-34`)

## Commands
This module exposes NO `commands/*.sh` (no `commands/` directory). Its user-facing surface is
the set of bash **library** verbs in `libs/bashlib.sh`, invoked by many other modules. Listed
here because they are the module's real API.

| verb (bash fn) | hint / usage | behavior | side effects |
|---|---|---|---|
| `get DAT ARG [OPA]` | read a value | runs `main.js get`; returns 0 with value on stdout, 100 for a missing optional value, other = error | none (read); on exit 100 emits `err` only when `$CMD` is `get`/`exec-function` (bashlib.sh:20-49) |
| `put DAT ARG OPA [VAL]` | write/delete a field | `main.js put`; `VAL` unset deletes field, `"true"`/`"false"` coerced to bool, else string | rewrites `users.json`/`containers.json`; then `datastore_push` git-commit (bashlib.sh:51-60) |
| `out DAT ARG [json]` | dump record as shell vars | `main.js out`; echoes `VAR='value'` lines (or `out container X json`) | none; output captured to config files (bashlib.sh:62-71) |
| `cfg container C add_mapped_port\|update_ip …` | run an internal mutating fn | `main.js cfg` dispatches to `container_add_mapped_port`/`container_update_ip` | rewrites `containers.json` (bashlib.sh:73-82, main.js:132-138) |
| `del DAT ARG` | delete a record | `main.js del` (stdout not captured) | rewrites json; `datastore_push` (bashlib.sh:84-93) |
| `new container\|user\|reseller ARG [T] [B]` | create a record | `main.js new` -> `lib.js new_*` | allocates ip/uid/ids, rewrites json; `datastore_push` (bashlib.sh:9-18) |
| `add container C user\|vncuser NAME` | append to array field | `main.js add` (stdout not captured) | rewrites `containers.json` (bashlib.sh:95-104, main.js:157-174) |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/pre-init.sh` | pre-init | sets defaults `SC_DATASTORE_RO_DIR=/var/srvctl3/gluster/srvctl-data`, `SC_DATASTORE_RW_DIR=/var/srvctl3/datastore`, `SC_DATASTORE_RO_USE=true`, `SC_DATASTORE_DIR=$RO_DIR`; makes RO/RW dirs `readonly` |
| `hooks/init.sh` | init | if `$SC_USE_GLUSTER`: `gluster_mount_data srvctl-data $RW_DIR` and set `SC_DATASTORE_RO_USE=false` on success; else `SC_DATASTORE_RO_USE=false`; then `init_datastore` (picks RW vs RO dir, seeds files, exports `SC_DATASTORE_DIR`) |
| `hooks/update-install-host.sh` | update-install-host | if `$SC_USE_GLUSTER`: `gluster_configure srvctl-data $RW_DIR`; then `install_datastoreserver` (writes+enables the systemd unit) |
| `hooks/diagnose.sh` | diagnose | prints `/etc/srvctl/hosts.json` |

## Libs
`libs/bashlib.sh` — the verb wrappers `new get put out cfg del add` (used by ~all modules,
159 call sites across modules). These are the core data API.
`libs/datalib.sh` — `publish_data` (rsync `/etc/srvctl/data` to every `cluster host_list`
host over ssh), `grab_data <host>` (reverse), `init_datastore_install` (root-only: mkdir RO/RW
dirs + `/etc/srvctl/data`, seed hosts/containers/users json, `git init` the RW dir with a
`.gitignore`, mkdir `users/` and `cert/`), `init_datastore` (choose RO vs RW dir, seed if
missing, `export SC_DATASTORE_DIR`). `publish_data`/`grab_data` are registered for
`sc exec-function` (comment at datalib.sh:3) but have no in-repo callers.
`libs/gitlib.sh` — `datastore_push "<verb args>"`: warns if RO, else `git add ./*.json &&
git commit` in RW dir and appends a line to `.git.log`. Called by `new/put/del`.
`libs/httpserverlib.sh` — `install_datastoreserver`: writes `/etc/systemd/system/
datastore-server.service`, `daemon-reload`, enable+start+status.
`lib.js` — the big generator/allocator library (exported functions consumed by `main.js`,
which many modules reach via `get`/`out`/`cfg`). Notable exports used across the codebase:
`container_uid/br/gw/interface/br_host_ip/bridge/user_id/hostnet/host/host_ip/reseller/
http_port/https_port/resolv_conf/ethernet/ethernet_network/hosts/quota/useruids/nspawn/
br_netdev/br_network/firewall_commands/mx/domains`, `cluster_etc_hosts/postfix_relaydomains/
host_keys/user_list/container_list/host_list/host_ip_list`, `user_container_list`,
`new_user/new_reseller/new_container`, `container_update_ip`, `container_add_mapped_port`,
`write_users/write_containers`, `user_uid`. `container_user` (lib.js:269) is defined but NOT
exported → dead code. `apps/datastore-server.js` — standalone HTTP daemon (no exports).

## Config & templates
No `conf/` directory. `default-users.json` is the seed user table (root + single-letter
resellers a–x with reseller_id/user_id/uid/name), copied to `$SC_DATASTORE_DIR/users.json`
by `init_datastore_install` when no `users.json` and no `/etc/srvctl/data/users.json` exist
(datalib.sh:81-90). The systemd unit for `datastore-server.service` is generated inline in
`httpserverlib.sh` (not a file template) and written to `/etc/systemd/system/`.

## State touched
Host paths: `$SC_DATASTORE_RO_DIR` (`/var/srvctl3/gluster/srvctl-data`),
`$SC_DATASTORE_RW_DIR` (`/var/srvctl3/datastore`) incl. `.git/`, `.git.log`, `.gitignore`,
`users/`, `cert/`, `pki-validation/`; `/etc/srvctl/data/` (+ `hosts.json`, `containers.json`,
`users.json` seed sources); `/etc/srvctl/hosts.json` (read by diagnose). Container paths read
by `lib.js`: `/srv/<C>/rootfs/etc/passwd`, `/srv/<C>/rootfs/etc/group`, `/srv/<C>/rootfs`.
systemd units: `datastore-server.service` (created, enabled, started). Network: HTTP listener
on `127.0.0.1:1030` (haproxy backend `srvctl3data`); rsync-over-ssh to cluster hosts; derives
the whole `10.<hostnet>.<user_id>.<c>` container IP scheme and `10.15.<hostnet>.0` mesh hosts.
Datastore keys: everything under `hosts.json` / `users.json` / `containers.json`.

## Dependencies
Core helpers: `exif`, `err`, `ntc`, `msg`, `run` (lablib.sh); `run_hook`/`load_libs` sourcing;
`$SC_INSTALL_DIR`, `$SC_USER`, `$NOW`, `$HOSTNAME`, `$CMD`, `$SC_HOSTNET`,
`$SC_COMPANY_DOMAIN`, `$SRVCTL`. Node side requires `../../lablib.js` (msg/ntc/err/get/run/rok)
and `os`/`fs`/`http`. Other modules assumed: `containers` (activation + main consumer),
`gluster` (`gluster_mount_data`/`gluster_configure`, gated by `$SC_USE_GLUSTER`), `haproxy`
(routes `.well-known/pki-validation` + `.well-known/srvctl/datastore/` to port 1030;
`proxylib.sh` writes `$SC_DATASTORE_DIR/pki-validation`). External binaries: `/bin/node`,
`git`, `rsync`, `ssh`, `systemctl`. NOTE `$SC_USE_GLUSTER` is referenced by init/update hooks
but is never assigned anywhere in the repo (it is auto-derived as `SC_USE_<MODULE>` only for
directory-named modules by `test_srvctl_modules`; there is no `gluster` value produced here
because the module dir is `gluster` → `SC_USE_GLUSTER` IS produced by commonlib for the
gluster module). Confirmed `SC_USE_GLUSTER` is set by `commonlib.sh:474` module loop.

## Bugs & smells
- **medium — lib.js:16,115,130 (readonly guard is dead).** `write_users`/`write_containers`
  block writes only `if (SC_DATASTORE_RO)`, read from `process.env.SC_DATASTORE_RO`. That env
  var is never exported anywhere in the repo (bash uses `SC_DATASTORE_RO_USE`, unexported).
  Result: in readonly mode `put`/`new`/`del`/`add`/`cfg` still write the JSON files to
  `$SC_DATASTORE_DIR` (the RO dir); only the git commit is skipped by `datastore_push`
  (gitlib.sh:5-7). The JS-level readonly protection never fires. Harm: silent writes to the
  "readonly" gluster datastore.
- **medium — main.js:157-174 (duplicate ADD blocks → racing double write).** Two separate
  `if (CMD === ADD)` blocks. For `add container X vncuser Y` the first block runs
  `datastore.write_containers()` BEFORE the vncuser is pushed (writing a stale file), then the
  second block pushes and writes again. Two async `fs.writeFile` on the same file race; the
  outcome depends on completion order. `exit()` and `write_containers()` are invoked twice per
  ADD. Harm: nondeterministic persisted state / lost update under concurrency.
- **low — lib.js:448,464 (crash on missing port).** `container_add_mapped_port` does
  `var port_arg = process.argv[7]; … port_arg.indexOf(":")`. If invoked without a port arg
  `port_arg` is `undefined` and `.indexOf` throws an uncaught `TypeError` instead of a clean
  `return_error`. (Author flagged it: "TODO .. fix this fix", lib.js:451.)
- **low — bashlib.sh:87-90,98-101 (del/add lose error detail).** `del`/`add` declare
  `local __result` but never assign it (node output goes straight to stdout), so the
  `exif "…EXIT ($?) $__result"` diagnostic is always missing the node error text that
  `new`/`get`/`put`/`out` capture via `2>&1`.
- **low — lib.js:857 (debug print in production path).** `new_container` does
  `console.log(C, T, B)`; stray debug output on every container creation (captured by bashlib
  `new` via `2>&1`, but still noise).
- **low (security) — apps/datastore-server.js:34 (path traversal).** `hash_file =
  "/var/srvctl3/datastore/pki-validation/" + req.url.substring(28)` with no sanitization; a
  crafted `.well-known/pki-validation/../../..` URL could read files outside the directory.
  Server is behind haproxy but the endpoint is internet-reachable for ACME.
- **low — dead code.** `container_user` (lib.js:269) not exported; commented-out
  `get_reseller_id` (lib.js:758); unused constants `SC_HOSTS_DATA_FILE`/`SC_RESELLER_USER`/
  `SC_DATASTORE_RO` in main.js:29-34; `SC_ON_HS`/`ON_HS` computed but unused (lib.js:28-30).
- **low — undeclared globals.** `SC_USER` (main.js:36-37, lib.js:22-23), `NOW`, `ON_HS`
  assigned without `var/const/let` (implicit globals; would throw under strict mode).

## Polish risks
- `get` exit-code contract: `0` = value (printed), `100` = missing optional value, other =
  error. Many callers `|| exit`/`|| return` on this; the `100` special-case in bashlib.sh:38-45
  and main.js `return_value` (main.js:59-65) / `process.exitCode = 100` must be preserved.
- `main.js` error prefix `MAIN-ERROR:` + exit code `110` (main.js:67-71); `lib.js`
  `LIB-ERROR:` + exit `112` (lib.js:42-46); default `process.exitCode = 99` (main.js:53).
- `out` output format: `VAR='value'` with `-`→`_` in the variable name and object values
  `JSON.stringify`'d (main.js:73-77); `out container` emits `C='…'`, `out host` emits
  `SC_HOSTNAME='…'` + `SC_<KEY_UPPER>='…'` (main.js:145-148, 253-257). Consumers source this.
- `out container X json` prints pretty JSON with 4-space indent (main.js:79-82, 141-143);
  used by `backupcontainerlib.sh:13`.
- Container IP scheme `10.<SC_HOSTNET>.<user_id>.<c>`, `c` starting at 2, `>250` is fatal
  (lib.js:742-756, 806-812). `container_uid = 65536*(user_id*255 + c)` (lib.js:144-151).
- Interface naming by first octet: `192.a.b.c`→`a_b_c`, `172`→`a+b+c`, else `b-c-d`
  (lib.js:176-185). Bridge default `10.<b>.<c>.x` (lib.js:155-162).
- `datastore-server.js` listens on port **1030** and serves exactly
  `/.well-known/srvctl/datastore/containers.json` and `/.well-known/pki-validation/<file>`
  (apps/datastore-server.js:8,33,60); haproxy hardcodes `127.0.0.1:1030`.
- `datastore_push` appends `"$NOW $SC_USER <commit-output> <args>"` lines to
  `$SC_DATASTORE_RW_DIR/.git.log` and commits with message `"$SC_USER@$HOSTNAME <args>"`
  (gitlib.sh:10); `.gitignore` = `.git.log` + `.gitignore` (datalib.sh:97-100).
- systemd unit name `datastore-server.service`, `User=root`, `Restart=always`,
  `RestartSec=3`, `WantedBy=multi-user.target`, `ExecStart=/bin/node …/apps/datastore-server.js`
  (httpserverlib.sh:7-24).
- Default paths `/var/srvctl3/gluster/srvctl-data` (RO) and `/var/srvctl3/datastore` (RW),
  `SC_DATASTORE_RO_USE` defaulting to `true` (pre-init.sh:6-12).
- `container_quota` default `250000000` (lib.js:396-403); `container_http_port` 80 /
  `container_https_port` 443 defaults (lib.js:280-294); resolv.conf appends `8.8.8.8`/`8.8.4.4`
  (lib.js:296-305).
- `default-users.json` exact contents (root + a–x resellers, ids/uids) — the seed table when
  no users.json exists (datalib.sh:88).

## v4 notes
- Bash verb wrappers (`bashlib.sh`) each spawn a fresh `node` process per call → very high
  process-spawn cost across the 159 call sites. In v4 a persistent `.mjs` datastore service
  (or a single node invocation batching operations) would remove per-call startup.
- `main.js` is a hand-rolled argv dispatcher with repeated `if (CMD === …)` ladders and a
  duplicated ADD block; collapse into a single command table and share the RO/write-guard and
  bool-coercion logic. Merge the two ADD blocks and fix the double `write_containers`.
- Unify readonly enforcement: pick ONE variable (`SC_DATASTORE_RO_USE`) and enforce it in the
  writer (JS or service) rather than the dead `SC_DATASTORE_RO` guard.
- `lib.js` mixes pure derivation (uid/br/gw/interface/domains) with side-effecting writers and
  string-template generators for nspawn/network/hosts/firewall files. In `.mjs` split into:
  a pure model/derivation module, a persistence layer, and per-artifact template generators.
  The template generators overlap heavily with what the `containers`/`haproxy` modules consume
  via `get`/`out` — good candidates to move behind typed functions.
- `container_add_mapped_port`'s argv juggling (three fallback positions + `udp:`/`tcp:` parse)
  is fragile; take an explicit `{proto,port,comment}` object in v4.
- Duplication: `return_error`/`return_value` are defined in BOTH `main.js` and `lib.js` with
  slightly different exit codes; `SC_*` env re-reads duplicated across both files; the
  `SC_USE_GLUSTER` gate + `gluster_*` calls are copy-pasted between the `datastore` and
  `static` modules' init/update hooks.
- `publish_data`/`grab_data` (rsync mesh sync) and the `datastore-server.js` public snapshot
  are two overlapping "share the data" mechanisms; consolidate the cluster-sync story.
