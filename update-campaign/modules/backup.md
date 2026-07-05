# Module "backup" — v3 fact sheet (commit 988c38c)

## Purpose
Library-only module providing shell functions for ad-hoc/scripted backups: rsync mirror
backups of directories from the local host (`local_backup`), from a remote server
(`server_backup`), or from a host reachable only through an ssh jump/proxy host
(`remote_backup`), plus a (currently disabled) 7z-based per-container archive backup
(`local_container_7z_backup`). It exposes no CLI commands and no hooks; the functions are
intended to be called from root/user custom command scripts (`/root/srvctl-includes/*.sh`,
`$SC_HOME/srvctl-includes/*.sh`) or via `sc exec-function <fn> <args>` (root-only path in
commonlib.sh:123-128). Comment at libs/sclib.sh:316: "either add your own settings here, or
source this file". Distinct from the `backupdb` module and from
`modules/containers/libs/backupcontainerlib.sh` (`backup_ve`), which are separate units.

## Activation
`module-condition.sh` is just `echo true` (modules/backup/module-condition.sh:3), so the
module is unconditionally enabled (`SC_USE_BACKUP=true` cached in modules.conf via
`test_srvctl_modules`, commonlib.sh:404-479). Both lib files are therefore sourced on every
srvctl invocation by `load_libs` (commonlib.sh:47-66). `libs/7zlib.sh` self-disables with
`return` at line 8 if `/usr/bin/7z` is absent; `libs/sclib.sh` always loads and sets the
`SC_BACKUP_PATH=/backup` default globally (sclib.sh:3).

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | (no `commands/` directory; module contributes no CLI commands) | - |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| - | - | (no `hooks/` directory) |

## Libs
| function (file:line) | provided by | notes / external use |
|---|---|---|
| `local_container_7z_backup C [dest]` (7zlib.sh:14) | 7zlib.sh | 7z-archive backup of container `C` to `$BACKUP_PATH/$HOSTNAME/$C` (or `$2`): filelist, creation-date stamp, packagelist + `srvctl backup-db clean` via ssh if container answers, then `7z u -uq0` archives of cert, rootfs/srv, home, root, etc, var, var/lib/mysql. **Entire body after line 28 is dead: bare `exit` (added in e179f53, 2026-07-04) terminates the process.** Renamed from `run_local_container_7z_backup` between 3.1.4.3 and 3.1.5.0. No in-repo callers. |
| `display_backup_geometry host dir ssize dsize scount dcount` (sclib.sh:8) | sclib.sh | `msg` + append line to `$SC_HOME/.srvctl/backup.log`. Only called by the three backup functions below. |
| `local_backup dir...` (sclib.sh:22) | sclib.sh | Per dir: validate `-d`, log start, `mkdir -p` target parent under `$SC_BACKUP_PATH/$HOSTNAME`, skip if `systemctl status`-grep finds a matching rsync, on TTY compute du/find geometry, then `rsync --progress --delete-after -a` and log OK/ERROR. No in-repo callers. |
| `server_backup host dir...` (sclib.sh:103) | sclib.sh | Probes `ssh -n -o BatchMode=yes $host hostname` (returns on failure); per dir same pattern but source is `$host:$i`, target `$SC_BACKUP_PATH/<remote hostname>`, rsync `--progress --delete-after -avze ssh`. No in-repo callers. |
| `remote_backup proxy host dir...` (sclib.sh:201) | sclib.sh | Probes nested `ssh proxy ssh host hostname`; per dir source `root@$host:$i`, transport `-e "ssh -A $proxy ssh"`, rsync `--progress --delete-after -avz`. No in-repo callers. |

No other module or core file references any of these functions (`grep` over repo). Reachability
in production is only via `exec-function`, custom includes, or manual sourcing.

## Config & templates
- (no `conf/` directory)
- Reads env/config vars: `BACKUP_PATH` (7zlib.sh:11, default `/backup`; was `/mnt/backup`
  before e179f53) and `SC_BACKUP_PATH` (sclib.sh:3, default `/backup`) — expected to come from
  `/etc/srvctl/*.conf`. No key named `backup` appears in `example-conf/`.

## State touched
- Host paths written: `$SC_BACKUP_PATH/$HOSTNAME/...` and `$SC_BACKUP_PATH/<remote-hostname>/...`
  (rsync mirrors, `--delete-after` deletes vanished files); `$BACKUP_PATH/$HOSTNAME/$C/*.7z`,
  `filelist`, `packagelist`, `creation-date` (7z path, currently dead);
  `$SC_HOME/.srvctl/backup.log` (append-only log, sclib.sh:10,38,90,92,134,188,190,232,288,290).
- Container paths read (7z path): `/srv/$C/cert`, `/srv/$C/rootfs/{srv,home,root,etc,var,var/lib/mysql}`,
  `/srv/$C/creation-date`, `/srv/$C/rootfs/var/log/dnf.log`.
- Inside container (7z path): runs `srvctl backup-db clean` and `dnf list installed` via ssh.
- systemd units: none created; `systemctl status` (full tree) is parsed as a concurrency guard.
- Network: ssh to container hostname (7zlib.sh:34), ssh/rsync-over-ssh to backup source hosts,
  agent-forwarded (`ssh -A`) nested ssh through proxy hosts.

## Dependencies
- Core helpers: `msg`, `ntc`, `err` (lablib.sh:23,28,87), `run` (lablib.sh:93, echoes command
  then executes `$*` unquoted), `nur` (lablib.sh:117, prints the command only — used as a
  visible "about to run" banner before the real rsync).
- Core vars: `NOW` (init.sh:60, `%Y.%m.%d-%H:%M:%S`), `HOSTNAME`, `SC_HOME` (init.sh:134),
  `SC_TTY` (srvctl.sh:21-24, executed as `if $SC_TTY`).
- Other modules: none required. Overlaps conceptually with `modules/containers/libs/backupcontainerlib.sh`
  (`backup_ve`, uses `SC_BACKUP_PATH` and `SC_BACKUP_HOST`) and the `backupdb` module.
- External binaries: `rsync`, `ssh`, `du`, `find`, `systemctl`, `grep`, `7z` (p7zip, gated at
  7zlib.sh:6), `dnf` (inside container, dead path).

## Bugs & smells
- **high 7zlib.sh:28** — bare `exit` (no-op disable added in e179f53) makes
  `local_container_7z_backup` terminate the whole srvctl process with status 0 (last command
  before it is the `if [[ $2 ]]` compound, status 0) before creating anything. Any caller —
  `sc exec-function local_container_7z_backup C` from cron, or a custom include script —
  silently gets "success" while no backup is made and the rest of the calling script is never
  executed. Lines 30-91 are dead code.
- **medium 7zlib.sh:11** — uses `BACKUP_PATH` while every other backup path in the codebase
  keys off `SC_BACKUP_PATH` (sclib.sh:3, modules/containers/libs/backupcontainerlib.sh:8).
  An admin who configures `SC_BACKUP_PATH=/mnt/big` gets rsync backups there but 7z container
  archives still under `/backup` — divergent backup locations and a non-`SC_`-prefixed var
  violating the project convention.
- **medium sclib.sh:48 (also 142, 240)** — concurrency guard
  `systemctl status | grep rsync | grep "$target" | grep -c "$i"` is a substring match over the
  whole process tree: backing up `/srv` while any rsync involving `/srv2` (or any process whose
  cmdline happens to contain both strings) is visible makes the guard fire and `continue`,
  silently skipping that directory's backup for as long as the collision persists.
- **medium sclib.sh:90 (also 188, 288)** — outside a TTY (cron) the geometry block is skipped,
  so `source_size`/`destination_size`/`source_count`/`destination_count` are empty and every
  non-interactive "OK"/error log line is written as `#size: / files: /`, degrading the only
  success record the module produces.
- **low sclib.sh:190, 290** — failure log lines in `server_backup` and `remote_backup` are
  labeled `local-backup-failure` (copy-paste from line 92), so remote failures are
  indistinguishable from local ones when grepping `backup.log`.
- **low sclib.sh:33, 128, 226** — `for i in $args` / `$dirs` word-splits and glob-expands:
  directory arguments containing spaces or glob characters are split into wrong paths; with
  `--delete-after` a wrong-but-existing target could even mirror-delete unrelated backup data.
- **low sclib.sh:230 vs 279** — `remote_backup` probes reachability as `$host` but rsyncs as
  `root@$host`; if the proxy's ssh config maps the host to a non-root user the probe passes and
  the transfer then fails auth (or vice versa).
- **low 7zlib.sh:42** (dead today, live if line 28 is removed) —
  `run ssh "$C" "dnf list installed" > "$to/packagelist"` redirects the `run` helper's output,
  so the ANSI-colored command-echo line (lablib.sh:102) lands inside `packagelist`, corrupting
  the package inventory.
- **smell sclib.sh:84, 180-181, 278-280, 27** — `t`, `s`, `p`, `args` are assigned without
  `local` in functions sourced into the main srvctl shell; calls leak/clobber these globals.
- **smell 7zlib.sh:34** — container liveness probe compares `ssh $C hostname` output to the
  short name `$C`; containers whose internal hostname is an FQDN are misdetected as "not
  running" (fallback to offline backup still proceeds, but `backup-db clean`/packagelist are
  skipped).

## Polish risks
- Function names are the public API (called from out-of-repo scripts and `exec-function`):
  `local_backup`, `server_backup`, `remote_backup`, `display_backup_geometry`,
  `local_container_7z_backup` (7zlib.sh:14; note it was already renamed once from
  `run_local_container_7z_backup`, so external callers may exist under either name).
- Defaults: `SC_BACKUP_PATH="/backup"` (sclib.sh:3), `BACKUP_PATH="/backup"` (7zlib.sh:11).
- Target directory layout: `$SC_BACKUP_PATH/$HOSTNAME/$(dirname $i)/` for local (sclib.sh:28,45,84),
  `$SC_BACKUP_PATH/<probed remote hostname>/...` for server/remote (sclib.sh:123, 222);
  7z layout `$BACKUP_PATH/$HOSTNAME/$C/{cert,srv,home,root,etc,var,var-lib-mysql}.7z` +
  `filelist`, `packagelist`, `creation-date` (7zlib.sh:21,48,42,52,60-89).
- Log file and exact line formats in `$SC_HOME/.srvctl/backup.log`:
  `$NOW $1:$2 #source-size $3 #destination-size $4 #source-files $5 #destination-files $6`
  (sclib.sh:10); `$NOW backup-local $i` (38); `$NOW OK local-backup $i #size: S/D files: C/C` (90);
  `$NOW !!! ERROR $? !! local-backup-failure: $i ...` (92, 190, 290 — same string in all three
  functions); `$NOW backup $host $i` (134); `$NOW OK $host $i ...` (188, 288);
  `$NOW backup $proxy -> $host $i` (232).
- User-visible strings: `"$i dont exists"` (sclib.sh:40, typo included),
  `"$i inaccessible on $host"` (136, 234), `"There is a process already running for this backup
  task."` (50, 144, 242), `"Calculating ..."` (58, 152, 250), `"OK backup done $HOST:$i"`
  (89, 187, 287), `"backup error ..."` (93, 191, 291), `"Connecting to ..."`/`"Connected to ..."`
  (110-116, 209-215), `"Local backup $args to $target"` (30), 7z-side `msg`/`ntc` labels
  (7zlib.sh:32,36,45,59,62,70,76,79,82,86).
- rsync invocations: `rsync --progress --delete-after -a "$i" "$t"` (sclib.sh:87),
  `rsync --progress --delete-after -avze ssh "$s" "$t"` (185),
  `rsync --progress --delete-after -avz -e "ssh -A $proxy ssh" "$s" "$t"` (285) — `--delete-after`
  mirror semantics must not change; each is preceded by an `nur` banner printing the identical
  command line (86, 182, 282).
- ssh probe options `-n -o BatchMode=yes` (sclib.sh:112,132,161,168,212,230,259,266) and
  `-n -o ConnectTimeout=1` (7zlib.sh:34); rsync source `root@$host:$i` for remote_backup (279).
- 7z switch string `7z u -uq0` (7zlib.sh:60,65,73,77,80,83,89) — update-mode archives that prune
  entries deleted from disk; changing to fresh-create alters archive history semantics.
- Error paths return/continue, never exit: connection failure → `return` (sclib.sh:117, 217),
  bad dir / busy task → `continue` (41, 53, 137, 147, 235, 245); the module itself must not
  abort a longer script (except the known line-28 landmine).
- `module-condition.sh` must emit exactly `true` on stdout (consumed by commonlib.sh:436-442).
- 7zlib.sh:6-9 `return`-when-no-`7z` must stay source-safe (file is sourced, not executed).

## v4 notes
- This is effectively a scripting toolkit, not a module: no commands, no hooks, no conf. In v4
  it maps naturally to a `backup.mjs` library (or a proper `sc backup ...` command family) with
  the three transport variants (local / ssh / ssh-via-jump) unified into one function with a
  transport parameter — the three bodies in sclib.sh are ~90% copy-paste of each other
  (validate, mkdir, busy-check, geometry, rsync, log).
- Duplication across modules: `modules/containers/libs/backupcontainerlib.sh` (`backup_ve`,
  rsync of `/srv/$C` to `SC_BACKUP_HOST`/local path) and the `backupdb` module implement
  overlapping per-container backup logic; v4 should have one backup subsystem with one config
  key set (`SC_BACKUP_PATH`, `SC_BACKUP_HOST`) instead of `BACKUP_PATH` vs `SC_BACKUP_PATH`.
- The concurrency guard should become a lock file (or `flock`) per target path instead of
  grepping `systemctl status`.
- Decide the fate of `local_container_7z_backup`: it has been dead-ended with `exit` and its
  mysql TODO (7zlib.sh:68) never materialized; either delete it in v4 or resurrect it as a
  documented archive-backup command (fixing the packagelist redirect and BACKUP_PATH naming).
- Geometry calculation (du/find on both ends) is expensive and TTY-only; in v4 rsync's own
  `--stats` output could feed the log line for both interactive and cron runs.
- The examples block (sclib.sh:302-316) is documentation pretending to be code; v4 should move
  it to real docs/help text.
