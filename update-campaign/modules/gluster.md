# gluster — v3 fact sheet (commit 988c38c)

## Purpose
Cluster shared-storage module: installs and configures **glusterfs-server** on containerfarm
hosts, issues TLS certificates for gluster's `secure-access` mode from the srvctl CA, creates
replicated gluster volumes (one brick per cluster host under `/glu/<datadir>/brick`), and
mounts them. It provides the library functions that the **datastore** module (volume
`srvctl-data` → `$SC_DATASTORE_RW_DIR`) and the **static** module (volume `srvctl-storage` →
`/var/srvctl3/storage`) call to get replicated storage, plus a read-only bind mount of the
local brick at `/var/srvctl3/gluster/<datadir>` used as the datastore RO fallback and by the
ssh module for pubkey lookup.

## Activation
`modules/gluster/module-condition.sh` — **the module is currently hard-disabled: every code
path echoes `false`.**

Logic as written:
- `false` if `$HOSTNAME == localhost.localdomain` (line 5).
- Proceed only if `$SC_HOSTNET` set or `/etc/srvctl/data` exists (line 11).
- `false` inside a container (`systemd-detect-virt -c` = `systemd-nspawn` or `lxc`, lines 14–21).
- Host must appear in `/etc/srvctl/hosts.json` (line 23).
- `false` if the cluster has only one host (awk brace-depth counter, line 32; the explanatory
  comment at line 29 says `d==1` but the code tests `d==2`).
- The final "all checks passed" branch echoes `false` with `#echo true` commented out
  (lines 38–39). This disable was introduced in commit e179f53 ("Checkpoint fabelous",
  2026-07-04), the commit immediately before 988c38c; from 3.1.5.1 (2017) until then it
  echoed `true`.

Consequence: `SC_USE_GLUSTER=false` in `modules.conf` on every host, so libs are never
loaded and hooks never run. The `$SC_USE_GLUSTER` branches in datastore/static hooks are
dead at this commit.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | module has no `commands/` directory | - |

(Manual entry points are `sc exec-function gluster_reset <datadir>` etc. via
`run_command`'s exec-function path, commonlib.sh:123–128 — only when the module is enabled.)

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/diagnose.sh` | `run_hooks diagnose` from `modules/srvctl/commands/diagnose.sh:91` | Prints "Diagnose for gluster - the cloud filesystem." then `run gluster peer status` and `run gluster volume status all`. Read-only. |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` from `modules/srvctl/commands/update-install.sh:83` | Bails (return 0) if `SC_ROOTCA_HOST` unset (lines 6–10). On the CA host: `root_CA_init gluster`, creates client cert `root` + server certs for `$HOSTNAME` and every `get cluster host_list` member, installs CA cert and own server key/crt into `/etc/ssl/gluster-{ca.crt,server.key,server.crt}.pem` (lines 14–36). On non-CA hosts: probes CA over ssh (line 40) and rsyncs the missing `/etc/ssl/gluster-*.pem` files from `root@$SC_ROOTCA_HOST:/etc/srvctl/CA/...` (lines 49–65). Then generates `/etc/ssl/dhparam.pem` if absent (lines 85–88) and calls `gluster_install` (line 90). |

## Libs
`libs/glusterlib.sh` — all four functions are defined for external use; none are called
inside the gluster module itself except `gluster_install` (from the hook):
- `gluster_reset <datadir>` (3–20): stops/deletes the volume, removes the brick, stops
  glusterd; tells the operator a reboot is required. Not referenced anywhere; manual
  exec-function tool.
- `gluster_install` (22–37): `sc_install glusterfs-server`, symlinks
  `/etc/ssl/glusterfs.{ca,pem,key}` → the `gluster-*.pem` files, `touch
  /var/lib/glusterd/secure-access`, `firewalld_add_service glusterfs`, enables/starts
  glusterd, `gluster peer status`.
- `gluster_configure <datadir> <mountdir>` (39–127): **used by**
  `modules/datastore/hooks/update-install-host.sh:5` (`srvctl-data`) and
  `modules/static/hooks/update-install-host.sh:5` (`srvctl-storage`). Probes all cluster
  peers, builds a brick list of every host with `host_ip`+`hostnet` in the datastore,
  creates the volume `replica <hostcount>` with `force`, sets `client.ssl`/`server.ssl` on,
  starts it, then calls `gluster_mount_data`. If the volume already exists: reports ok
  (return 0) or force-starts it.
- `gluster_mount_data <datadir> <mountdir>` (130–207): **used by**
  `modules/datastore/hooks/init.sh:5` and `modules/static/hooks/init.sh:5` (i.e. runs at
  every srvctl init when enabled). Root-only (line 132, returns 1 otherwise). Verifies
  brick and `/etc/ssl/glusterfs.{ca,pem,key}` exist, force-starts the volume if a brick is
  offline (grep at line 162), creates the **ro bind mount** `/glu/<datadir>/brick` →
  `/var/srvctl3/gluster/<datadir>` (lines 172–179), then fuse-mounts
  `$HOSTNAME:/<datadir>` on `<mountdir>` with a log file (lines 184–196). Returns 0 iff
  the fuse mount is present (198–206).

`libs/glustercertlib.sh` — **dead code**: line 3 `## NOT USED ##`, line 4 `return` aborts
sourcing, so `init_gluster_rootca_certificates` / `grab_gluster_rootca_certificates`
(a "glusternet" variant writing under `/etc/glusterfs/`) are never defined.

## Config & templates
- (no `conf/` directory; nothing installed from templates)

## State touched
- Host packages/units: `glusterfs-server` rpm; `glusterd.service` enabled+started;
  `firewalld` service `glusterfs` opened.
- Host paths: `/glu/<datadir>/brick` (brick, deleted/recreated in reset/configure);
  `/var/srvctl3/gluster/<datadir>` (ro bind mount of brick); `<mountdir>` fuse mount
  (`/var/srvctl3/datastore` for srvctl-data via datastore, `/var/srvctl3/storage` via
  static); `/etc/ssl/gluster-ca.crt.pem`, `/etc/ssl/gluster-server.{key,crt}.pem`,
  symlinks `/etc/ssl/glusterfs.{ca,pem,key}`, `/etc/ssl/dhparam.pem`;
  `/var/lib/glusterd/secure-access`; `/var/log/gluster-<datadir>-mount-$NOW.log`;
  CA store `/etc/srvctl/CA/ca/gluster.crt.pem` and
  `/etc/srvctl/CA/gluster/{server,client}-<host>.{key,crt}.pem` (CA host only).
- Datastore keys read: `get cluster host_list`, `get host <h> host_ip`,
  `get host <h> hostnet`.
- Network: gluster peer probe / volume traffic among cluster hosts; ssh+rsync as root to
  `$SC_ROOTCA_HOST`.
- Downstream consumers of its mounts: `modules/datastore/hooks/pre-init.sh:6`
  (`SC_DATASTORE_RO_DIR=/var/srvctl3/gluster/srvctl-data`),
  `modules/ssh/sshd_authorization.sh:11` (reads
  `/var/srvctl3/gluster/srvctl-data/users/$_user/*.pub`).

## Dependencies
- Core helpers: `msg`, `ntc`, `err`, `debug`, `run`, `eyif` (lablib.sh); hook/lib loading
  via `run_hook`/`load_libs` gated on `SC_USE_GLUSTER` (commonlib.sh:47–108).
- Other modules (functions assumed present, i.e. those modules must be enabled):
  **ca** — `root_CA_init`, `create_ca_certificate` (modules/ca/libs/calib.sh:46,68) and
  `SC_ROOTCA_HOST` (modules/ca/hooks/pre-init.sh:6);
  **datastore** — `get` (modules/datastore/libs/bashlib.sh:20);
  **srvctl** — `sc_install` (modules/srvctl/libs/fedoralib.sh:6);
  **firewalld** — `firewalld_add_service` (modules/firewalld/libs/firewalldlib.sh:3).
- External binaries: `gluster`, `glusterd` (mount helper `mount.glusterfs`), `systemctl`,
  `openssl`, `rsync`, `ssh`, `setfattr`, `attr`, `mount`, `awk`, `systemd-detect-virt`.

## Bugs & smells
- **medium** modules/gluster/module-condition.sh:38-39 — final branch is `echo false` with
  `#echo true` commented out, so the module can never activate (disabled in e179f53, the
  previous commit). Looks like a deliberate kill-switch, but it silently turns off gluster
  replication, the `/var/srvctl3/gluster/*` RO mounts and cert renewal on every cluster
  host; nothing warns that the module's downstream consumers (datastore RO dir, ssh pubkey
  lookup) now point at unmounted paths.
- **medium** modules/gluster/libs/glusterlib.sh:141,148,153,158 — the "no brick" and
  "missing /etc/ssl/glusterfs.*" error paths end with `err` + bare `return`; `err` exits 0
  (lablib.sh:87-91) so `gluster_mount_data` returns **success**. Caller
  modules/datastore/hooks/init.sh:5-8 then sets `SC_DATASTORE_RO_USE=false`, making the
  datastore use the (unmounted, unreplicated) RW dir even though gluster is broken.
- **medium** modules/gluster/hooks/update-install-host.sh:40,52-64 — the reachability probe
  disables host-key verification (`UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no`),
  but the actual `rsync -e ssh` transfers use default ssh settings; on a fresh host whose
  root has no known_hosts entry for the CA, unattended `update-install` blocks on an
  interactive host-key prompt. The probe itself is MITM-able while fetching CA material.
- **low** modules/gluster/libs/glusterlib.sh:7 — `run umount /srvctl/data` is a stale
  hardcoded path (real mountpoint is `$SC_DATASTORE_RW_DIR` = `/var/srvctl3/datastore`,
  modules/datastore/hooks/pre-init.sh:9); reset stops and deletes the volume while it is
  still fuse-mounted.
- **low** modules/gluster/libs/glusterlib.sh:12 — `attr -R -r glusterfs.volume-id .`
  operates on the caller's current working directory, not the brick; the intended xattr
  cleanup target is `/glu/<datadir>/brick` (the following setfattr lines partially cover it,
  but `.glusterfs` internals under a kept brick are not).
- **low** modules/gluster/libs/glusterlib.sh:162 — offline-brick detection greps the exact
  column spacing `'N/A       N/A        N       N/A'` from `gluster volume status`; any
  gluster CLI format change silently disables the force-restart of offline bricks.
- **low** modules/gluster/libs/glusterlib.sh:47-48 — glusterd inactive is reported with
  `err` but `return 0`, so datastore/static `update-install-host` hooks proceed as if the
  volume were configured.
- **low** modules/gluster/hooks/update-install-host.sh:3-4 — documented invocation
  `sc exec-function run_module_hook gluster update-install` is doubly broken:
  `run_module_hook` was removed (commented out at commonlib.sh:69-83) and the hook was
  renamed to `update-install-host`.

## Polish risks
- `SC_USE_GLUSTER` is derived from the directory name (commonlib.sh:53); renaming the
  module breaks modules/datastore/hooks/{init,update-install-host}.sh:3 and
  modules/static/hooks/{init,update-install-host}.sh:3.
- module-condition.sh must emit literally `true`/`false` on stdout (consumed by
  test_srvctl_modules, commonlib.sh:436-442) — and at this commit the correct baseline
  output is `false` on all paths (module-condition.sh:38-39,45).
- Function names and signatures called cross-module: `gluster_configure <datadir> <mountdir>`
  (datastore/hooks/update-install-host.sh:5, static/hooks/update-install-host.sh:5) and
  `gluster_mount_data <datadir> <mountdir>` (datastore/hooks/init.sh:5,
  static/hooks/init.sh:5). `gluster_mount_data`'s exit code contract — 0 iff mounted
  (glusterlib.sh:202) else 1 (glusterlib.sh:205) — drives `SC_DATASTORE_RO_USE`
  (datastore/hooks/init.sh:5-9). Preserve the current (buggy) 0-returns at
  glusterlib.sh:141-159 during pure polish, or fix consistently with the datastore session.
- Path scheme: brick `/glu/<datadir>/brick` (glusterlib.sh:81,91,139), RO bind mount
  `/var/srvctl3/gluster/<datadir>` (glusterlib.sh:172-178) — consumed verbatim by
  modules/datastore/hooks/pre-init.sh:6 and modules/ssh/sshd_authorization.sh:11.
- Cert/key filenames: `/etc/ssl/gluster-ca.crt.pem`, `/etc/ssl/gluster-server.{key,crt}.pem`
  (hooks/update-install-host.sh:23-26,52-64), symlink targets `/etc/ssl/glusterfs.{ca,pem,key}`
  (glusterlib.sh:26-28), `/var/lib/glusterd/secure-access` (glusterlib.sh:29),
  CA store paths `/etc/srvctl/CA/ca/gluster.crt.pem`,
  `/etc/srvctl/CA/gluster/server-<host>.{key,crt}.pem`
  (hooks/update-install-host.sh:23-26,52-64), `/etc/ssl/dhparam.pem`
  (hooks/update-install-host.sh:85-88), CA "net" name `gluster` passed to
  `create_ca_certificate` (hooks/update-install-host.sh:18-20,34).
- Volume options and shape: `replica ${#lista[@]} ... force` (glusterlib.sh:99),
  `client.ssl on` / `server.ssl on` (glusterlib.sh:102-103), `start ... force`
  (glusterlib.sh:105,120,167); firewalld service name `glusterfs` (glusterlib.sh:30).
- `run rsync "$options" ...` (hooks/update-install-host.sh:52,58,64) only works because
  `run` expands `$*` unquoted (lablib.sh:104-105), re-splitting the option string
  `--no-R --no-implied-dirs -avze ssh` (hooks/update-install-host.sh:47). A rewrite that
  quotes arguments properly passes one bogus argument and rsync fails.
- Load-bearing grep patterns on external output: mount-table checks
  `" on /var/srvctl3/gluster/$datadir"` (glusterlib.sh:172) and
  `"$HOSTNAME:/$datadir on $mountdir type fuse.glusterfs"` (glusterlib.sh:184,198);
  offline-brick pattern `'N/A       N/A        N       N/A'` (glusterlib.sh:162).
- Mount log filename `/var/log/gluster-$datadir-mount-$NOW.log` (glusterlib.sh:187) with
  `$NOW` = `%Y.%m.%d-%H:%M:%S` (init.sh:60).
- Hook filenames `diagnose.sh` / `update-install-host.sh` are bound to `run_hooks diagnose`
  (modules/srvctl/commands/diagnose.sh:91) and `run_hooks update-install-host`
  (modules/srvctl/commands/update-install.sh:83).
- User-visible strings worth keeping stable: `"[ OK ] Gluster mounted $datadir"`
  (glusterlib.sh:189), `"A reboot is required to reset gluster properly."`
  (glusterlib.sh:19), `"A srvctl module needs /glu/$datadir for a gluster brick"`
  (glusterlib.sh:124), `"Diagnose for gluster - the cloud filesystem."`
  (hooks/diagnose.sh:3).

## v4 notes
- Decide the module's fate first: it is hard-disabled at baseline (module-condition.sh:39).
  Either delete it in v4 (and the `$SC_USE_GLUSTER` branches in datastore/static plus the
  `/var/srvctl3/gluster/srvctl-data` consumers in ssh/sshpiperd) or restore it as a
  first-class storage backend behind an explicit config flag instead of a commented-out line.
- `libs/glustercertlib.sh` is dead (top-level `return` at line 4) — drop it.
- The cert distribution logic (CA host generates, others rsync-pull missing files) is
  duplicated between hooks/update-install-host.sh and the dead glustercertlib.sh, and the
  same generate-or-pull pattern exists in other modules (ca/hostnet certs); a shared
  "fetch cert from CA host" helper (or .mjs service) would remove three near-copies.
- Cluster topology iteration (`get cluster host_list` + `get host X host_ip/hostnet`)
  appears twice inside `gluster_configure` alone; in .mjs this is one datastore query
  returning a host array.
- Replace mount-table and gluster-CLI output greps with `findmnt --json` and
  `gluster ... --xml` (or gluster's JSON output) — the whitespace-sensitive grep at
  glusterlib.sh:162 is the fragile core of the health check.
- Fix the error-path return codes in `gluster_mount_data` and `gluster_configure` so
  callers can trust them; today datastore compensates with its own `SC_DATASTORE_RO_USE`
  default rather than the function's result.
- Note for the datastore/static sessions: `if $SC_USE_GLUSTER` (datastore/hooks/init.sh:3
  et al.) evaluates as **true** when the variable is empty (empty command = exit 0), e.g.
  with a stale modules.conf that predates the module list — a v4 module gate should be an
  explicit string comparison.
- `gluster_reset` is an operator tool with no command wrapper; if kept, promote it to a
  proper `## @en`-documented root command with an `argument`/confirmation guard instead of
  exec-function.
