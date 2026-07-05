# module mariadb — v3 fact sheet (commit 988c38c)

## Purpose
Client-side MariaDB/MySQL helper library. Provides functions (no CLI commands of its own) to install/enable mariadb-server, check root connectivity, secure the server with a generated root password, create per-site databases+users with saved credentials, and dump all databases to `/root/mariadb-dump/`. Consumed by the `backupdb` module (database backups) and the `wordpress` module (DB provisioning during `install-wordpress`). Primarily intended to run **inside containers** (see comment `hooks/init.sh:3` "in containers").

## Activation
`module-condition.sh:3-9`: prints `true` if `systemctl is-active mariadb.service` reports `active`; otherwise it **sources `modules/ve/module-condition.sh`**, which prints `true` when `systemd-detect-virt -c` reports `systemd-nspawn` or `lxc`. Net effect: enabled on any host where mariadb is actively running, and **unconditionally inside every container** (whether or not mariadb is installed there). The condition runs in a subshell via `test_srvctl_modules` (`commonlib.sh:436`), result cached as `SC_USE_MARIADB` in `modules.conf`.

## Commands
- (none — the module ships no `commands/` directory)

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/init.sh` | `init` (every srvctl invocation, when module enabled) | If `/etc/mysqldump.conf` exists, sets `SC_MARIADB_DUMP_CONF=/etc/mysqldump.conf` (lines 5-10). Redundant with the fallback default in the lib (`libs/mariadblib.sh:8-11`). |

## Libs
`libs/mariadblib.sh` — sourced by `load_libs` when enabled, and additionally **sourced directly by path** from `modules/backupdb/libs/backupdblib.sh:9` (`source "$SC_INSTALL_DIR"/modules/mariadb/libs/mariadblib.sh`), so the file path itself is an API.

| function | used by | behavior |
|---|---|---|
| `setup_mariadb` (13-25) | wordpress `install-wordpress.sh:63` | `sc_install mariadb-server` + `add_service mariadb` (enable/restart/status). |
| `check_mariadb_connection` (27-45) | all other lib functions | Sets **global** `SC_MDA` to `--defaults-file=/etc/mysqldump.conf` if the file exists, else `-u root`; runs `mysql $SC_MDA -e status`; on failure `err` + bare `exit` (line 43). |
| `backup_mariadb` (48-81) | backupdb `backupdblib.sh:10` | Wipes `/root/mariadb-dump/*`, then dumps each database (except `information_schema`, `performance_schema`) into `/root/mariadb-dump/<%Y_%m_%d__%H_%M_%S>/<db>.sql`; `exif` after each dump. Sets global `BACKUP_POINT`. |
| `add_mariadb_db` (84-135) | wordpress `install-wordpress.sh:64` | Sanitizes name (`.`/`-`→`_`, line 100), truncates user to 15 / db to 63 chars (102-103). If `/etc/mariadb-$db_name.conf` exists: reads `pwd:` line and returns early (105-111). Else generates password (`get_password`), `CREATE DATABASE IF NOT EXISTS`, `GRANT ALL ... IDENTIFIED BY`, writes conf file with `dbf:`/`usr:`/`pwd:` lines (129-132). Leaves globals `dbd`, `db_name`, `db_usr`, `db_pwd` for callers (wordpress reads `db_usr`/`db_pwd` at `install-wordpress.sh:79,82`). |
| `secure_mariadb` (137-180) | **no callers found in repo** | If `/etc/mysqldump.conf` exists, `cat`s it; else deletes anonymous/remote-root users, drops `test` DB, sets root password via `UPDATE mysql.user SET Password=PASSWORD(...)`, logs the password, appends `[client]\nuser=root\npassword=...` to `/etc/mysqldump.conf`. |
| `mysql_root` (182-192) | **no callers found in repo** | `mysql $SC_MDA -e $1` (unquoted) or interactive `mysql $SC_MDA`. |

File ends with top-level `return` at line 194; lines 196-269 are **dead code** (a second, sc2-era `secure_mariadb` definition, never parsed).

## Config & templates
- (no `conf/` directory)
- Files it *creates* at runtime: `/etc/mysqldump.conf` (mysql `[client]` defaults with root password, `mariadblib.sh:168-173`) and `/etc/mariadb-<db_name>.conf` (`dbf:`/`usr:`/`pwd:` lines, `mariadblib.sh:129-132`).

## State touched
- Host/container paths: `/etc/mysqldump.conf`, `/etc/mariadb-<db>.conf`, `/root/mariadb-dump/<timestamp>/*.sql` (previous contents deleted each run), `/etc/srvctl/system/mariadb.service` symlink (via `add_service`, `modules/srvctl/libs/fedoralib.sh:33`).
- systemd: `mariadb.service` enabled + restarted (`setup_mariadb`).
- MySQL state: databases/users/grants created; `mysql.user` rows deleted/updated; `test` DB dropped (secure path).
- Log: `$SC_LOG` via `log`/`err` — including plaintext root DB password (`mariadblib.sh:165`).
- Network: none beyond localhost mysql socket; dnf install fetches packages.

## Dependencies
- Core helpers: `msg`, `ntc`, `err`, `log`, `run`, `nur`, `exif` (lablib.sh).
- Other modules (functions assumed loaded by `load_libs`): `get_password` (modules/password — condition is always `true`), `sc_install` + `add_service` (modules/srvctl `fedoralib.sh`/`systemdlib.sh` — fedoralib returns early unless `$ID == fedora`, so `setup_mariadb` breaks on non-Fedora).
- External binaries: `/usr/bin/mysql`, `mysqldump`, `dnf`, `systemctl`, `grep`, `tr`, `date`.
- Consumers: `modules/backupdb` (sources lib by path), `modules/wordpress` (`setup_mariadb`, `add_mariadb_db`, globals `db_usr`/`db_pwd`).

## Bugs & smells
- **high** `libs/mariadblib.sh:43` — `exit` with no status after `err` (which succeeds) exits **0** on "CONNECTION FAILED"; automated callers (backupdb backups) see success while no backup was made — silent backup failure.
- **medium** `libs/mariadblib.sh:55` — `rm -fr /root/mariadb-dump/*` destroys the previous dump generation *before* the new dumps are produced; if a subsequent `mysqldump` fails (`exif` at :75 aborts mid-loop), zero or partial dumps remain and the outer file-backup then archives that. The timestamped dir (:57) falsely suggests retained generations.
- **medium** `libs/mariadblib.sh:159-163` (also 153-157) — `UPDATE mysql.user SET Password=PASSWORD(...)` and `DELETE FROM mysql.user` fail on MariaDB ≥ 10.4 where `mysql.user` is a non-updatable view (Fedora ships 10.5/10.11); `secure_mariadb` can never secure a modern server, and the DELETE/DROP failures at 153-157 are unchecked/silent.
- **medium** `libs/mariadblib.sh:129-132` and `:168-173` — credential files `/etc/mariadb-<db>.conf` and `/etc/mysqldump.conf` are created with default umask (0644 for root): plaintext DB passwords world-readable by any unprivileged user inside the container.
- **medium** `libs/mariadblib.sh:102` — `db_usr="${dbd:0:15}"`: two sites whose sanitized names share the first 15 chars collide; the second `add_mariadb_db` re-runs `GRANT ... IDENTIFIED BY '<new pwd>'` (:122) which resets the existing user's password and breaks the first site's DB access.
- **low** `libs/mariadblib.sh:165` — root DB password written in plaintext to `$SC_LOG` (`log "Set database root password to: $password"`); also echoed to terminal at :109 and :134.
- **low** `libs/mariadblib.sh:187` — `mysql $SC_MDA -e $1` with unquoted `$1`: any query containing a space word-splits (e.g. `mysql_root "show databases"` becomes `-e show databases`), so `mysql_root` is broken for real queries (currently uncalled).
- **low** `libs/mariadblib.sh:69` — `grep -v Database` intended to strip the header also skips any database whose name contains "Database"; unquoted word-splitting breaks on exotic names.
- **low** `libs/mariadblib.sh:116,122` — SQL assembled by string interpolation from `$1`/`$HOSTNAME`; names not matching the sanitizer (`:100` only maps `.` and `-`) pass through into SQL (root-local, so injection impact limited to self-foot-gun/breakage).
- smell: `libs/mariadblib.sh:196-269` dead second `secure_mariadb` after top-level `return` (:194); `hooks/init.sh` duplicates the lib's default; `exif` at :75 called without a message → empty error text on dump failure.

## Polish risks
- File path API: `modules/mariadb/libs/mariadblib.sh` is sourced by absolute path from `modules/backupdb/libs/backupdblib.sh:9` — moving/renaming it breaks backupdb. File must stay `source`-safe (top-level `return` at `mariadblib.sh:194`, no side effects beyond `SC_MARIADB_DUMP_CONF` default at :8-11).
- Global variable contracts: `SC_MDA` set by `check_mariadb_connection` (`mariadblib.sh:32,35`) and consumed by every other function; `db_usr`/`db_pwd`/`db_name`/`dbd` left as globals for wordpress (`install-wordpress.sh:79,82`); `BACKUP_POINT` global (`mariadblib.sh:57`).
- Credential file formats must stay byte-compatible: `/etc/mariadb-<db_name>.conf` lines exactly `dbf:<db>`, `usr:<user>`, `pwd:<password>` — re-read via `grep 'pwd:'` + `${db_pass:4}` offset (`mariadblib.sh:107-108`); `/etc/mysqldump.conf` `[client]` section with `user=root` / `password=...` (`mariadblib.sh:169-172`) — consumed by `mysqldump --defaults-file` and by `modules/wordpress/scripts/restore-wordpress-password.sh:20-29`.
- Name derivation must be identical (existing production DBs/users depend on it): `tr '.' '_' | tr '-' '_'` (`mariadblib.sh:100`), user = first 15 chars, db = first 63 chars (:102-103); default name = `$HOSTNAME` (:95); wordpress uses `<host first label>_wp` (`install-wordpress.sh:51`).
- Idempotency contract: `add_mariadb_db` returns early without touching MySQL when `/etc/mariadb-$db_name.conf` exists (`mariadblib.sh:105-111`).
- Backup layout: `/root/mariadb-dump/$(date +%Y_%m_%d__%H_%M_%S)/<db>.sql`, prior contents wiped first (`mariadblib.sh:55-57,74`); `information_schema`/`performance_schema` excluded (:70).
- Exit behavior: `check_mariadb_connection` terminates the whole srvctl process on failure (`mariadblib.sh:43`) — today with status **0**; changing to nonzero alters observable behavior of backup automation (probably desired, but it is a behavior change).
- Activation semantics: module on whenever mariadb.service is active OR running inside an nspawn/lxc container (`module-condition.sh:3-9`); `SC_MARIADB_DUMP_CONF` default `/etc/mysqldump.conf` (env-respected if preset, `mariadblib.sh:8-11`).

## v4 notes
- This is a pure library module (no commands, trivial hook) — in v4 it collapses naturally into a `mariadb.mjs` service class (connect / ensureServer / ensureDatabase / dumpAll / secure) invoked from backupdb and wordpress equivalents; keep a thin bash shim only if containers must stay node-free.
- Duplication to erase: `check_mariadb_connection` logic re-implemented inline in `modules/wordpress/scripts/restore-wordpress-password.sh:20-43`; dead sc2 `secure_mariadb` copy (`mariadblib.sh:196-269`); `hooks/init.sh` vs lib default of `SC_MARIADB_DUMP_CONF`.
- Modern MariaDB (≥10.4, unix_socket auth for root) makes the password-securing dance obsolete: root@localhost via socket needs no password and no `/etc/mysqldump.conf`; v4 could drop `secure_mariadb` (already caller-less) and use `ALTER USER`/`CREATE USER` + `GRANT` instead of `GRANT ... IDENTIFIED BY` and view-breaking `UPDATE mysql.user`.
- Credentials belong in one 0600 store (datastore or `/etc/srvctl/`) as JSON, not scattered `/etc/mariadb-*.conf` 0644 files; passwords must stop flowing into `$SC_LOG`.
- Backup rotation: dump into a temp dir and atomically swap, or keep N generations, instead of rm-before-dump; make failures return nonzero to the caller instead of `exit` 0.
- Reconsider the 15-char user truncation (MariaDB supports 80-char user names since 10.x) — but any change must migrate existing grants.
