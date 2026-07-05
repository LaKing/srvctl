# backupdb — v3 fact sheet (commit 988c38c)

## Purpose
Provides a single library function, `backupdb()`, that dumps local databases to `/root`:
MariaDB (by sourcing the mariadb module's `backup_mariadb`) and MongoDB (via a **vendored**
`mongodump` binary, mongo-tools r3.6.0 / Go 1.9.1, dated 2017-11-26, shipped because the
Fedora mongo-tools build was broken — RH bugzilla 1537510, referenced at
`libs/backupdblib.sh:18`). The module ships no commands, no hooks, no conf. It is intended
to run *inside* the machine that owns the data (host or container), invoked as
`sc exec-function backupdb` (root-only dispatch in `commonlib.sh:123-128`).

Files:
- `module-condition.sh` (3 lines)
- `libs/backupdblib.sh` (35 lines)
- `bin/` — 8 vendored x86_64 ELF binaries (~54 MB): bsondump, mongodump, mongoexport,
  mongofiles, mongoimport, mongorestore, mongostat, mongotop. Vendored third-party code;
  only `mongodump` is referenced by any script (`libs/backupdblib.sh:30`).

## Activation
`module-condition.sh:3` is unconditionally `echo true`. The module is therefore enabled on
every host, container, and user context; `SC_USE_BACKUPDB=true` is cached in
`/var/local/srvctl/modules.conf` / `~/.srvctl/modules.conf` (`commonlib.sh:404-450`), and
`load_libs` (`commonlib.sh:47-65`) sources `libs/backupdblib.sh` on every srvctl invocation.

## Commands
- (module has no `commands/` directory; the only entry point is `sc exec-function backupdb`,
  root-only, via `run_command` in `commonlib.sh:123-128`)

## Hooks
-

## Libs
| function | file | provides | used elsewhere? |
|----------|------|----------|-----------------|
| `backupdb()` | `libs/backupdblib.sh:3-35` | If `/var/lib/mysql` dir and `/usr/bin/mysql` exist: prints `ntc "mariadb @ $HOSTNAME"`, re-sources `$SC_INSTALL_DIR/modules/mariadb/libs/mariadblib.sh` by absolute path, calls `backup_mariadb` (dumps each DB to `/root/mariadb-dump/<ts>/<db>.sql`, exits via `exif` on mysqldump failure). If `/var/lib/mongodb` dir exists: prints `ntc "mongodb @ $HOSTNAME"`, wipes `/root/mongodb-dump/*`, then runs vendored `$SC_INSTALL_DIR/modules/backupdb/bin/mongodump --out /root/mongodb-dump/<%Y_%m_%d__%H_%M_%S>` | **No in-repo caller.** The intended automated caller `run ssh "$C" "srvctl backup-db clean"` (`modules/backup/libs/7zlib.sh:38`) references a command that does not exist anywhere (and that caller function is itself dead behind a stray `exit` at `7zlib.sh:28`). Documented in `documentation.md:335,1361-1365`. `modules/containers/commands/recreate-ve.sh:35` does its own `ssh "$C" mongodump` — the container's binary, not this module's. |

## Config & templates
- (no `conf/`; the `bin/` directory of vendored mongo-tools is the module's only payload
  besides the lib, used in place, never installed anywhere)

## State touched
- `/root/mongodb-dump/*` — deleted on every run (`libs/backupdblib.sh:27`), then
  `/root/mongodb-dump/<%Y_%m_%d__%H_%M_%S>/` created and filled by mongodump (:28-30).
- Via mariadb branch: `/root/mariadb-dump/*` wiped and `/root/mariadb-dump/<ts>/<db>.sql`
  written; reads `/etc/mysqldump.conf` (`SC_MARIADB_DUMP_CONF`); writes `$SC_LOG`
  (`~/.srvctl/srvctl.log`) via `log` (`mariadblib.sh:53-77`).
- Network: mongodump default connection to local mongod (127.0.0.1:27017); mysql via local
  socket. No systemd units, no datastore keys.

## Dependencies
- Core helpers: `ntc` (`lablib.sh:28`); `$SC_INSTALL_DIR`, `$HOSTNAME`; dispatch via
  `exec-function` (`commonlib.sh:123`).
- Other modules: hard path-dependency on `modules/mariadb/libs/mariadblib.sh`
  (`libs/backupdblib.sh:9`) — sourced regardless of `SC_USE_MARIADB`; that lib pulls in
  `msg/err/run/nur/exif/log`, `get_password`, `sc_install` semantics.
- External binaries: vendored `bin/mongodump` (r3.6.0, x86_64-only ELF); `/usr/bin/mysql`,
  `mysqldump` (mariadb branch); `date`, `mkdir`, `rm`. A `sc_install mongo-tools` fallback
  is commented out (`libs/backupdblib.sh:23-26`).

## Bugs & smells
- **high** `modules/backupdb/libs/backupdblib.sh:27` — `rm -fr /root/mongodb-dump/*` deletes
  the only existing MongoDB dump *before* the new dump is attempted; if mongodump fails
  (mongod down, auth, incompatible server) the machine is left with zero backups.
- **medium** `modules/backupdb/libs/backupdblib.sh:30` — mongodump exit status is never
  checked (no `exif`/`eyif`); a failed/partial dump leaves an empty timestamp directory and
  no error handling, so automation cannot distinguish success from failure (inconsistent
  with the mariadb branch, which hard-exits via `exif` at `mariadblib.sh:75`).
- **medium** `modules/backupdb/libs/backupdblib.sh:30` — unconditionally uses vendored
  mongo-tools r3.6.0 (2017) even when a current `/usr/bin/mongodump` exists; 3.6-era tools
  are incompatible with modern mongod (4.2+) and the binaries are x86_64-only, so on
  current MongoDB the dump fails — after the old dump was already deleted (see first bug).
- **medium** `modules/backupdb/libs/backupdblib.sh:13` — MongoDB detection keys only on
  `/var/lib/mongodb` (Fedora package datadir); installs from mongodb.org RPMs use
  `/var/lib/mongo`, so those databases are silently never backed up.
- **medium** `modules/backup/libs/7zlib.sh:38` (cross-module, reachability of this unit) —
  the only automated invocation is `srvctl backup-db clean`, but no `backup-db` command
  exists in any module (the unit only defines the *function* `backupdb`); inside the
  container this prints `Invalid command. backup-db` and exits 1, so DB dumps never run as
  part of container backups. The `clean` argument is likewise handled nowhere.
- **low** `modules/backupdb/libs/backupdblib.sh:28` — `out_path` is not `local`; sourcing
  the lib call leaks a global variable into the srvctl process.
- **low** `modules/backupdb/module-condition.sh:3` — unconditional `echo true`: module and
  its lib load on every machine including ones with no databases; `SC_USE_BACKUPDB` carries
  no information.

## Polish risks
- Function name `backupdb` (`libs/backupdblib.sh:3`) — operators invoke it as
  `sc exec-function backupdb`; it is documented (`documentation.md:335,1361`). Must keep.
- Exact notice lines `ntc "mariadb @ $HOSTNAME"` (`libs/backupdblib.sh:7`) and
  `ntc "mongodb @ $HOSTNAME"` (`libs/backupdblib.sh:15`).
- Dump path and layout `/root/mongodb-dump/$(date +%Y_%m_%d__%H_%M_%S)`
  (`libs/backupdblib.sh:28`) — documented at `documentation.md:1365`; restore procedures /
  operator habits depend on it. Same timestamp format as mariadb's `BACKUP_POINT`
  (`mariadblib.sh:57`).
- Wipe-before-dump semantics (`libs/backupdblib.sh:27`): at most one dump generation is
  kept; external disk-space assumptions may rely on this.
- Detection predicates: `[[ -d /var/lib/mysql ]] && [[ -f /usr/bin/mysql ]]`
  (`libs/backupdblib.sh:5`) and `[[ -d /var/lib/mongodb ]]` (`libs/backupdblib.sh:13`).
- Vendored binary path `$SC_INSTALL_DIR/modules/backupdb/bin/mongodump`
  (`libs/backupdblib.sh:30`) — the binaries must keep working from that path until replaced.
- `module-condition.sh:3` must output exactly `true` (parsed by `commonlib.sh:436-442`);
  changing it flips `SC_USE_BACKUPDB` in cached `modules.conf`.
- Absolute-path source of `modules/mariadb/libs/mariadblib.sh` (`libs/backupdblib.sh:9`)
  works even when `SC_USE_MARIADB=false`; a rewrite must not make the mariadb branch depend
  on module enablement.
- mariadb branch failure behavior: `backup_mariadb` **exits the whole process** via `exif`
  on any mysqldump error (`mariadblib.sh:75`), so the mongo branch is skipped in that case.

## v4 notes
- Merge into one backup engine (.mjs): detect engines (mysql socket, mongod, psql later),
  dump to a temp dir, verify non-empty/exit-0, atomically rotate keeping N generations —
  fixes the wipe-before-dump data-loss window by construction.
- Drop the 54 MB of 2017 vendored mongo-tools from git (only `mongodump` is ever used;
  bsondump/mongostat/mongotop/etc. are pure dead weight). Use the container's own
  `mongodump` (pattern already used in `modules/containers/commands/recreate-ve.sh:35`) or
  install `mongodb-database-tools` on demand; the 2018 Fedora build bug that motivated
  vendoring is long fixed.
- Reconcile the naming split: create a real `backup-db` command (with `## @en` help) that
  wraps the function, so `modules/backup/libs/7zlib.sh:38` finally works and the function
  stops being `exec-function`-only.
- Deduplicate the rm-all + timestamp-dir pattern shared with `backup_mariadb`
  (`mariadblib.sh:55-58`) into one rotation helper.
- Make the module condition meaningful (test for DB presence) or absorb the whole unit into
  the `backup` module — a 35-line lib with no commands/hooks barely justifies module
  overhead.
