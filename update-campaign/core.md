# CORE (root-level files) — v3 fact sheet (commit 988c38c)

Unit scope: `/srv/srvctl/srvctl.sh`, `init.sh`, `commonlib.sh`, `lablib.sh`, `push.sh`,
`claude.sh`, legacy JS (`server.js`, `lablib.js`, `encode.mjs`), `example-conf/`
(plus the gitignored `live-conf/` sibling and repo dotfiles `.gitignore`, `.jshintrc`).

## Purpose
The core is the srvctl bootstrap and runtime: `srvctl.sh` is the CLI entry point
(installed as `/bin/sc` and `/bin/srvctl` symlinks), `init.sh` performs environment
setup / config sourcing / module activation / init hooks, `commonlib.sh` provides the
module engine (condition caching, lib loading, hook runner, command dispatch, help
extraction), and `lablib.sh` provides colorized output, logging and error-handling
primitives used by every module. `lablib.js` is the Node-side twin of lablib.sh for the
~12 module JS apps. `push.sh`, `claude.sh`, `encode.mjs` are developer tools; `server.js`
(root level) is a dead placeholder. `example-conf/` holds bootstrap/config templates.

## Activation
Core is not a module; it always runs. Full execution flow:

**1. srvctl.sh (entry)**
- srvctl.sh:18-25 — `SC_TTY=true|false` via `tty`.
- srvctl.sh:27-31 — if root, TTY, and `/bin/pop` exists: execute `/bin/pop` (dev auto-resync hook) before anything else.
- srvctl.sh:34-39 — `HOSTNAME` readonly, fallback `uname -n`.
- srvctl.sh:43 — `DEBUG=false` default (later overridable by `/etc/srvctl/debug.conf` and `/etc/srvctl/*.conf`, frozen readonly at init.sh:153).
- srvctl.sh:47-54 — `SC_STARTTIME` (ms epoch), `SC_INSTALL_BIN=$(realpath $BASH_SOURCE)`, `SC_INSTALL_DIR="${SC_INSTALL_BIN:0:-10}"` (strips the 10 chars of `/srvctl.sh`), `SC_COMMAND_ARGUMENTS="$*"`; exports `SC_INSTALL_DIR`.
- srvctl.sh:56-75 — builds `SC_MODULES` (space-joined dir list): first `/root/srvctl-includes/modules/*` (root-defined custom modules), then `$SC_INSTALL_DIR/modules/*` (alphabetical). Order matters for dispatch shadowing.
- srvctl.sh:79-90 — `CMD=$1` lowercased (`${CMD,,}`), `ARG=$2` (not lowercased), `ARGS="$*"`, `OPA=$3`, `OPAS="${@:2}"` (args 2..N joined).
- srvctl.sh:92-100 — shortcut aliases on both `CMD` and `ARG`: `?`→status, `+`→start, `-`→stop, `!`→restart.
- srvctl.sh:103-104 — `SRVCTL="srvctl-$(cat version)"` (e.g. `srvctl-3.2.5.9`), readonly; this is the guard token every module script checks (`[[ $SRVCTL ]] || exit 10`).
- srvctl.sh:107 — sources init.sh (on failure only echoes "Init could not be loaded!" and continues — see smells).

**2. init.sh (environment + module activation)**
- init.sh:6 — sources `/etc/srvctl/debug.conf` if present (can set `DEBUG=true`).
- init.sh:8-12 — root: `mkdir -p /etc/srvctl /var/local/srvctl`.
- init.sh:15-45 — if installed at `/usr/local/share/srvctl`: create `/bin/sc`, `/bin/srvctl` symlinks and `/etc/bash_completion.d/srvctl-completion` → `modules/srvctl/completion.sh` (via `sudo ln -s` when sudo exists — attempted by any user on every run until the links exist).
- init.sh:48-49 — `SC_LOG=~/.srvctl/srvctl.log`, `mkdir -p ~/.srvctl`.
- init.sh:53,57 — sources `lablib.sh` then `commonlib.sh` (failures only echo a warning).
- init.sh:60-61 — `NOW=$(date +%Y.%m.%d-%H:%M:%S)` readonly, exported.
- init.sh:63-106 — **update-install / test-modules preamble** (only for those two CMDs): `dnf -y install nodejs` / `git` if missing; `rm -fr /var/local/srvctl/modules.conf`; if `/etc/srvctl/data/clusters.json` exists, copy it to `/etc/srvctl/clusters.json`, run `node modules/containers/host-conf.js` (generates `/etc/srvctl/host.conf` + `hosts.json`), source host.conf, chmod 644 both; then copy every `/etc/srvctl/data/*.conf` to `/etc/srvctl/` (prefix strip `${sourcefile:17}`).
- init.sh:110-116 — **config sourcing**: sources every `/etc/srvctl/*.conf` (bash syntax; sets SC_HOSTNET, SC_COMPANY, SC_ROOTCA_*, etc.).
- init.sh:118 — `source /etc/os-release` (provides ID/VERSION_ID to modules).
- init.sh:120-135 — `SC_USER` = `$SUDO_USER` if set else `$USER`; `SC_UID0` true/false; `SC_HOME` from `getent passwd`.
- init.sh:140-146 — logs the invocation to `$SC_LOG`; if root also appends `"$NOW [$SC_USER@$HOSTNAME $(pwd)]# srvctl $SC_COMMAND_ARGUMENTS"` to `/var/log/srvctl-root.log`.
- init.sh:148-157 — `CMD ARG ARGS OPA OPAS DEBUG` readonly; exports `SC_USER SC_UID0 SRVCTL` (+ `SC_HOME` at 135).
- init.sh:160 — `test_srvctl_modules` (module condition caching, below).
- init.sh:163-164 — hooks: `pre-init-$CMD` **before** `pre-init` (note asymmetry with post).
- init.sh:167-171 — help breakout: `man|help|-help|--help` → `help_commands; exit_0` (before libs are loaded).
- init.sh:178 — `load_libs` (sources `libs/*` of every enabled module).
- init.sh:182-186 — hooks: `init`, `post-init`, `post-init-$CMD`.
- init.sh:188-193 — `CMD == complicate` → `generate_completion` (from modules/srvctl lib) then `exit_0`.

**3. back in srvctl.sh — dispatch and exit**
- srvctl.sh:111-114 — `run_command` (see Commands); success → `exit_0` (prints `## $SRVCTL` trailer unless exec-function / DEBUG+TTY).
- srvctl.sh:119-124 — failure: `err "Invalid command. $CMD"` or `err "No-command."`.
- srvctl.sh:126-130 — `exec-function` that fell through (non-root or no args) prints a diagnostic line and `exit 1`.
- srvctl.sh:132-134 — `hint_commands` (command listing) and `exit 1`.

**modules.conf caching** (commonlib.sh:404-479): cache path is
`/var/local/srvctl/modules.conf` only when `SC_HOME` is empty; in practice always
`$SC_HOME/.srvctl/modules.conf` (root uses `/root/.srvctl/modules.conf` — CLAUDE.md's
"root uses /var/local" is doc drift). Regenerated when the file is missing or CMD is
`update-install`/`test-modules`: each module's `module-condition.sh` is sourced in a
subshell `$( )`; stdout `true` → enabled, anything else → disabled; a line
`export SC_USE_<NAME^^>=<true|false>` is **appended** to the cache. `test-modules`
exits 0 right after. Then both `/var/local/srvctl/modules.conf` (legacy) and the user
cache are sourced, and every `SC_USE_*` var is exported readonly (commonlib.sh:472-477).

## Commands
Core defines no `commands/*.sh`; it owns the **dispatch pipeline** (`run_command`,
commonlib.sh:116-205), tried in this order — first hit wins, each sourced **in the
current shell** followed by `exif` (so a non-zero return from the sourced script aborts
srvctl with that exit code):

| step | matcher | behavior | side effects |
|---|---|---|---|
| 0 | no `$CMD` (commonlib.sh:118) | `return 54` → "No-command." + `hint_commands`, exit 1 | - |
| 1 | root + `$OPAS` + `CMD==exec-function` (commonlib.sh:123-128) | executes `$OPAS` (a loaded shell function + args) in-shell | whatever the function does; JS apps use this via lablib.js `exec_function` |
| 2 | `CMD` ∈ new/get/put/out/cfg/del/add (commonlib.sh:131-137) | runs the datastore shell functions (`modules/datastore/libs/bashlib.sh`) as `$CMD $OPAS` | datastore reads/writes + cluster push; **the root+OPAS guard only binds to `new` — precedence bug, see Bugs** |
| 3 | `/root/srvctl-includes/$CMD.sh` (commonlib.sh:140-147) | root-defined custom command, sourced for any user who can see it | arbitrary |
| 4 | `$dir/commands/$CMD.sh` per module with `SC_USE_<MOD>=true`, in SC_MODULES order (commonlib.sh:150-169) | module command | arbitrary |
| 5 | `$SC_HOME/srvctl-includes/$CMD.sh`, non-root homes only (commonlib.sh:172-179) | user custom command | arbitrary |
| 6 | per-module `command.sh` defaults (commonlib.sh:184-202) | only `modules/containers/command.sh` (container ops; itself sources `modules/srvctl/command.sh` first) and `modules/srvctl/command.sh` (systemd service ops). They `exit_0`/`exit 0` themselves when they handle the invocation, else `return` | machinectl/systemctl operations |
| 7 | nothing matched | `return 250` → "Invalid command. $CMD" + `hint_commands`, exit 1 | - |

**Help extraction** (`## @en` machinery): marker constants at commonlib.sh:7-13 —
`HEMP='## @@@'` (syntax override), `HINT='## @en'` (one-line hint, must be within the
first 10 lines — `head | grep -m1` at :229), `HELP='## &en'` (multi-line help),
`HEXE='## &&&'` (dynamic help: the rest of the line is **executed** and its stdout,
newlines→`|`, shown as `[...]`, commonlib.sh:234-238). `hint_on_file`
(commonlib.sh:212-249) suppresses entries marked `root_only` / `hs_only` /
`reseller_only` in the first 20 lines (:219-223; a "reseller" is a 1-char username).
Rendering: `hint()` prints `   cmd` padded `%-40s` + ` hint` padded `%-48s` in green
(commonlib.sh:31-32). `${hintstr:7}` / `${command:0: -3}` strip the 7-char marker and
`.sh`. `help_commands` (commonlib.sh:334-402) prints the `## &en` blocks; `complicate()`
is a no-op (commonlib.sh:208-210) until `generate_completion`
(modules/srvctl/libs/completionlib.sh:6-27) redefines it and captures `hint_commands`
output into `/var/local/srvctl/completion/$USER.{hints,commands,arguments,VE}`, consumed
by `modules/srvctl/completion.sh`.

## Hooks
Core runs hooks, it does not provide hook files.

| engine piece | lifecycle point | what it does |
|---|---|---|
| `run_hook <name>` (commonlib.sh:85-108) | any | for each enabled module (SC_MODULES order) sources `hooks/<name>.sh`; `exif "$dir hook '<name>' failed"` after each — a hook whose last command returns non-zero aborts the whole CLI |
| `run_hooks <x>` (commonlib.sh:110-114) | any | `pre-x`, `x`, `post-x` |
| init.sh:163-164 | startup, before help breakout / lib loading | `pre-init-$CMD`, then `pre-init` |
| init.sh:182-186 | after `load_libs` | `init`, `post-init`, `post-init-$CMD` |
| (module-driven) | e.g. `adjust-service`, `update-install-host`, `update-install-ve`, `mkrootfs_*`, `firewalld`, `add_ve_create_nspawn_container` | invoked by module code through the core engine |

Note: command-level `pre-$CMD`/`post-$CMD` hooks exist only via `run_hooks`; plain
`run_command` does **not** wrap commands in hooks (CLAUDE.md's "pre-$CMD -> $CMD ->
post-$CMD" applies to `run_hooks` call sites, not to command dispatch).

## Libs
**lablib.sh** (sourced first, init.sh:53; no `$SRVCTL` guard): readonly colors
`RED GREEN YELLOW BLUE GRAY CLEAR`; `prg` (green line), `pry` (yellow line), `msg`
(`[ host ]` blue tag + green), `ntc` (tag + yellow), `log` (print + append `$SC_LOG`),
`logs` (silent log), `logfs` (log a file's content), `dbg` (counter + source:line),
`debug` (ms-since-start timing, only when `DEBUG && SC_TTY`), `trace`, `err` (append
`$SC_LOG` + red to stderr), `run` (echo prompt-style then execute `$*`, returns the
command's exit code; its failure warning is dead — see Bugs), `nur` (print only),
`exif` (exit-if-failed with `$?` propagation), `eyif` (warn-if-failed), `exit_0`
(prints `## $SRVCTL` trailer unless `CMD==exec-function` or DEBUG+TTY; exits 0),
`sed_file` (tmp-file line replace), `add_conf` (append-if-missing). Used by **all**
modules and core.

**commonlib.sh** (guarded `[[ $SRVCTL ]] || exit 10`, :4): `hint`, `title`,
`load_libs` (:47-66, sources `libs/*` of enabled modules), `run_hook`, `run_hooks`,
`run_command`, `complicate` (no-op default), `hint_on_file`, `hint_commands`,
`help_on_file`, `help_commands`, `test_srvctl_modules`, `set_permissions` (:481-497 —
chmods `/etc/srvctl` 755/644, `$SC_DATASTORE_RW_DIR` 755/644, `$SC_MOUNTS_DIR`/
`$SC_ROOTFS_DIR` 700; depends on datastore/containers module vars). All used by core;
`run_hooks`, `set_permissions`, `hint_commands` also called from modules
(e.g. modules/srvctl/commands/update-install.sh:15,83; completionlib.sh:38).

**lablib.js** — Node twin, required as `'../../lablib.js'` (path relative to the
requiring file) by module JS apps in codepad, containers, datastore, dns, haproxy,
letsencrypt, named, opendkim, perdition, ssh, usersonhost, vncproxy. Exports `msg`,
`ntc`, `err`, `get` (execSync capture), `run` (execSync echo), `rok` (boolean try),
`exec_function` (shells `$SC_INSTALL_DIR/srvctl.sh exec-function <fn>`; needs the
`SC_INSTALL_DIR` export from srvctl.sh:54 and the exec-function trailer suppression in
`exit_0`). Note `ntc`/`err` do NOT print the `[ host ]` tag (bash versions do).

**server.js** (root level) — single comment `// there is no spoon.`; nothing references
it (module `server.js` files under `modules/{gui,static,default,...}` are separate
files). Dead.

**encode.mjs** — dev tool run manually from a project root: merges all `.mjs/.sh/.js`
files (skipping `node_modules/.git/var/cert`, honoring `// @encode skip` first lines,
symlink-cycle safe) into `var/tools/<project>.<version>.txt` (the repo's `var/tools/`
exists for this). Not sourced/executed by srvctl.

**push.sh** — dev-only publisher, hardcoded to `/srv/codepad-project`: backs up to
`/srv/push-backup`, re-runs itself as `codepad`, increments `version` (awk), runs
shellcheck + `modules/srvctl/apps/beautify_bash.py` over all `*.sh` (suffix test uses
the arithmetic-comma trick `${file:0, -3 }` = last 3 chars), regenerates `README.md`
from `README.txt` + ANSI-stripped `srvctl help` output, and on `push.sh publish` does
`git add -A; git commit -m $(cat version); git push`. Writes `/tmp/urlconverter`,
`/tmp/srvctl-bash-beautify`.

**claude.sh** — one-liner dev wrapper: `claude --allowed-tools Bash,Read,Edit,WebFetch`.

## Config & templates
- `example-conf/pop.sh` — bootstrap installer: `dnf -y install git`, clone GitHub repo to `/usr/local/share/srvctl`, run `srvctl.sh`; with arg `dev` rsyncs the tree from `bp.d250.hu` instead. Deployed by hand (becomes `/bin/pop` on dev boxes, which srvctl.sh:30 then auto-runs).
- `example-conf/rock.sh` — load-test script (16 resellers, 32 users, ~150 `add-ve` calls).
- `example-conf/data/{branding.conf,ca.conf,clusters.json}` — templates for `/etc/srvctl/data/`; the update-install preamble (init.sh:87-105) materializes them into `/etc/srvctl/` (`clusters.json` → `host.conf`/`hosts.json` via `modules/containers/host-conf.js`; `*.conf` copied verbatim).
- `live-conf/` — gitignored (.gitignore:3) local copy with **real deployment data** (production clusters.json with public IPs, D250 branding, logo.svg); same layout as example-conf.
- `.jshintrc` — `{ "esversion": 6 }`; `.gitignore` — `node_modules/`, `@srvctl-2`, `live-conf`.

## State touched
- `/etc/srvctl/` — created (init.sh:10); all `*.conf` sourced every run (init.sh:110-116); `clusters.json`, `host.conf`, `hosts.json`, copied `*.conf` written during update-install preamble (init.sh:87-105).
- `/var/local/srvctl/` — created for root (init.sh:11); legacy `modules.conf` removed on update-install (init.sh:84) and sourced if present (commonlib.sh:458-462); `completion/` files via the complicate flow.
- `$SC_HOME/.srvctl/` — `srvctl.log` (every invocation, init.sh:140), `modules.conf` cache (commonlib.sh:418-448).
- `/var/log/srvctl-root.log` — every root invocation appended (init.sh:145).
- `/bin/sc`, `/bin/srvctl`, `/etc/bash_completion.d/srvctl-completion` — symlinks created on first run (init.sh:15-45).
- Packages: `dnf -y install nodejs git` during update-install/test-modules (init.sh:70,79).
- No systemd units, container paths, or network state touched by core itself (modules do that through hooks).

## Dependencies
- Bash ≥4 (`${CMD,,}`, `${!var}`, `${@:2}`, negative substrings).
- External binaries: `tty`, `uname`, `realpath`, `date`, `getent`, `ln`, `mkdir`, `chmod`, `cat`, `grep`, `head`, `sed`, `tr`, `basename`, optional `sudo`; `dnf`, `node`, `git` for update-install; push.sh additionally needs `awk`, `rsync`, `shellcheck`, `python`.
- `/etc/os-release` must exist (sourced unconditionally, init.sh:118).
- Module coupling baked into core: datastore verbs (`modules/datastore/libs/bashlib.sh`), `generate_completion` (modules/srvctl), `host-conf.js` (modules/containers), `completion.sh` (modules/srvctl), `set_permissions` uses `SC_DATASTORE_RW_DIR`/`SC_MOUNTS_DIR`/`SC_ROOTFS_DIR` from module libs, `hint_on_file` uses `SC_HOSTNET` from `/etc/srvctl/host.conf`.

## Bugs & smells
Real defects only, ranked:

1. **high commonlib.sh:383** — `help_commands` per-command lookup tests `[[ -f $dir/commands/$arg ]]` (missing `.sh`; the help call on the next line uses `$arg.sh`). No module ships extensionless command files (verified), so `sc help <any-module-command>` never matches and always prints `Pardon? '<cmd>' is not a command` — per-command help is broken for every module command (root/user custom commands still work). init.sh:169-170 then `exit_0`, so it even exits 0.
2. **high commonlib.sh:131** — `[[ $UID == 0 ]] && [[ $OPAS ]] && [[ $CMD == 'new' ]] || [[ $CMD == 'get' ]] || …` : because `&&` binds tighter than `||`, the root+has-args guard applies only to `new`. Any user running `sc get|put|out|cfg|del|add …` (even with no arguments) reaches the datastore shell functions directly; non-root invocations produce DATASTORE-ERROR/exif exits instead of "Invalid command", and the intended root-only gate on datastore mutation verbs is bypassed (practical damage limited only by file permissions on the datastore).
3. **medium lablib.sh:110** — inside `run`, `eyif` is called from the `then` branch of `if [[ … ]]`, so `eyif` captures `$?` of the just-succeeded condition (always 0) instead of `$__exitcode`; the warning `command '…' returned with an error` can never print (verified empirically). Additionally the exemption logic at lablib.sh:108 is inverted (`[[ $1 != systemctl ]] && [[ $2 != status ]] && [[ $code != 3 ]]` instead of negating the conjunction), so even if fixed naively, any failing `systemctl <anything>` or any `<cmd> status` would be exempt. All `run` failures are silent unless the caller follows with `exif`/`eyif`.
4. **medium commonlib.sh:231,234** — `head "$file" | grep -m 1 "$HEMP" "$file"`: grep is given a file operand, so the head-limited stdin is ignored and the **whole file** is searched for `## @@@` and `## &&&`. Consequence: a `## &&&` line anywhere in a command file (e.g. inside a heredoc/template) is executed via command substitution at commonlib.sh:237 every time `hint_commands` runs — i.e. on every mistyped command, bare `sc`, and completion regeneration. Unintended command execution + the 10-line header contract silently not enforced.
5. **medium commonlib.sh:448 (+init.sh:84)** — module cache regeneration appends (`>>`) without truncating. `update-install` removes only `/var/local/srvctl/modules.conf`, not `$SC_HOME/.srvctl/modules.conf`, so every update-install appends another full block of `export SC_USE_*` lines: the cache grows unboundedly and entries for renamed/removed modules persist forever (last-wins keeps current modules correct, but stale `SC_USE_OLDMODULE=true` stays exported).
6. **low commonlib.sh:352-358** — the full `sc help` listing iterates `SC_MODULES` without the `SC_USE_*` filter and without the `root_only`/`hs_only`/`reseller_only` filters used by `hint_on_file`, so it documents commands of disabled modules and root-only commands to ordinary users (inconsistent with the `hint_commands` listing).
7. **low commonlib.sh:104** — `run_hook` runs `exif` after sourcing each hook; a hook whose last statement is a benign failed conditional (e.g. trailing `[[ -f x ]] && y`) aborts the entire CLI with "hook '<name>' failed" and that conditional's exit code.
8. **low srvctl.sh:107** — `source init.sh || echo "Init could not be loaded!"` continues execution after a failed init; the subsequent `debug`/`run_command` calls then fail as unknown commands with confusing output instead of a clean abort.
9. **low init.sh:19-43** — for a non-root user on a host missing `/bin/sc`/`/bin/srvctl`/the completion symlink, every invocation runs `sudo ln -s …`, which can hang on a password prompt or spam sudo denials.
10. **low srvctl.sh:30** — if `/bin/pop` exists, **every** root TTY invocation executes it before dispatch (dev auto-resync backdoor); a stale pop.sh silently rewrites the installation at the start of unrelated commands.
11. **low lablib.js:51** — `get()`'s catch calls `e.stderr.toString()` without the `undefined` guard that `run()` has (lablib.js:62-63); a spawn-level failure (e.g. binary not found through the shell) makes the error handler itself throw a TypeError, masking the original error.
12. **low commonlib.sh:324-326** — `help_on_file` greps all `## @en` matches (no `-m 1`) into one string and strips the 7-char marker only once; a file with multiple `## @en` lines renders the extra lines with raw `## @en` markers inside the hint column.

## Polish risks
Exact behavior a rewrite must preserve (all verified at the cited lines):
- Marker strings and offsets: `'## @@@'`, `'## @en'`, `'## &en'`, `'## &&&'` with 7-char prefix stripping (commonlib.sh:7-13,242,245,326); `## &en` → 4-space indent replacement (commonlib.sh:329); `.sh` stripped via `${command:0: -3}` (commonlib.sh:242); `HINT` must sit in the first 10 lines, `root_only|hs_only|reseller_only` in the first 20 (commonlib.sh:219-229); dynamic help output wrapped `[out1|out2|]` (commonlib.sh:237).
- Hint layout: 3 leading spaces, `%-40s` command column, `%-48s` hint column, green (commonlib.sh:31-32) — `generate_completion` captures this output into `/var/local/srvctl/completion/$USER.hints` and `complicate()` parsing feeds `.commands`/`.arguments`/`.VE` read by `modules/srvctl/completion.sh:35-60`.
- Output prefixes: `msg`/`ntc`/`err` print `\e[34m[ ${HOSTNAME%%.*} ] ` + green/yellow/red text (lablib.sh:25,30,90); `err` goes to stderr and appends to `$SC_LOG` (lablib.sh:89-90); `run`/`nur` echo `[user@host dir]$|# cmd` (lablib.sh:102,126).
- Success trailer: `exit_0` prints `## $SRVCTL` (e.g. `## srvctl-3.2.5.9`) via `msg` for every successful command **except** `CMD==exec-function` or DEBUG-on-TTY (lablib.sh:163-173) — lablib.js `exec_function` (lablib.js:83-94) and other machine consumers rely on the suppression.
- `SRVCTL` value format `srvctl-$(cat version)` (srvctl.sh:103) — every module guard `[[ $SRVCTL ]] || exit 10` and comments suggest `/var/$SRVCTL` style use.
- Exit codes: 10 sourced-without-srvctl guard (commonlib.sh:4); `run_command` 54 (no command) / 250 (unknown) internally, both surfaced as final `exit 1` with `Invalid command. $CMD` / `No-command.` on stderr (srvctl.sh:119-134); `exif` exits with the failing command's exact code (lablib.sh:131-145); `sc help|man|-help|--help` and `sc complicate` exit 0 via `exit_0` (init.sh:167-171,188-193); `sc test-modules` exits 0 early (commonlib.sh:452-456); unknown `help ARG` returns 46 internally but still exits 0.
- Alias mapping `?`→status, `+`→start, `-`→stop, `!`→restart applied to both `$1` and `$2` (srvctl.sh:92-100); `CMD` lowercased, `ARG` not (srvctl.sh:81; help lowercases its arg at commonlib.sh:372).
- Dispatch precedence and ordering: exec-function → datastore verbs (`new get put out cfg del add`) → `/root/srvctl-includes/$CMD.sh` → module `commands/$CMD.sh` in SC_MODULES order (root custom modules **before** installed modules, srvctl.sh:60-75) → `$SC_HOME/srvctl-includes/$CMD.sh` (non-root only) → module `command.sh` defaults (containers before srvctl alphabetically; containers/command.sh sources srvctl/command.sh first). Commands are **sourced in the CLI shell** (can read/set CMD/ARG/OPAS, may `return`).
- Hook order: `pre-init-$CMD`, `pre-init` (in that order), help breakout, `load_libs`, `init`, `post-init`, `post-init-$CMD` (init.sh:163-186); `run_hooks` = pre-X, X, post-X (commonlib.sh:110-114); hooks run per-module in SC_MODULES order and abort via `exif` on failure.
- Cache format: lines `export SC_USE_<UPPERCASED_DIRNAME>=<true|false>` in `$SC_HOME/.srvctl/modules.conf` (and legacy `/var/local/srvctl/modules.conf`, sourced first), all vars exported readonly afterwards (commonlib.sh:448,458-477); regeneration triggers: file missing, `update-install`, `test-modules` (commonlib.sh:422).
- Exported env consumed elsewhere: `SC_INSTALL_DIR` (srvctl.sh:54; lablib.js:33), `SC_HOME`, `SC_USER`, `SC_UID0`, `SRVCTL`, `NOW` (init.sh:61,135,155-157).
- Log formats/paths: `$NOW [ $SC_USER@host ]: srvctl <args>` in `~/.srvctl/srvctl.log` (lablib.sh:43, init.sh:140); `$NOW [$SC_USER@$HOSTNAME $(pwd)]# srvctl <args>` in `/var/log/srvctl-root.log` (init.sh:145); `NOW` format `%Y.%m.%d-%H:%M:%S` (init.sh:60).
- Filesystem contracts: `/bin/sc`, `/bin/srvctl`, `/etc/bash_completion.d/srvctl-completion` symlink targets (init.sh:21-42); `/etc/srvctl/*.conf` sourced as bash; `/etc/srvctl/data/*` materialization incl. `chmod 644 host.conf hosts.json` (init.sh:97-98); `set_permissions` mode map (commonlib.sh:484-495).
- Messages other tooling may grep: `Usage: srvctl command [argument]` (commonlib.sh:253), `Pardon? '$ARG' is not a command` (commonlib.sh:398), `tested module: SC_USE_X=bool` (commonlib.sh:443), `srvctl command-completion has been updated for …` (init.sh:191).

## v4 notes
Ideas only — no behavior changes implied for the polish phase:
- The whole dispatch/help layer is grep-per-file on every invocation; in .mjs this becomes a build-once manifest (command name, hint, help, syntax, flags root_only/hs_only/reseller_only, module, path) generated from the `## @en` headers, with the CLI reading the manifest. Completion (`complicate`/`.hints` parsing) falls out of the same manifest instead of re-parsing colored terminal output.
- `test_srvctl_modules` + modules.conf is a hand-rolled cache with an append bug; v4 wants an atomic JSON write (`{module: bool}`) with explicit invalidation, and per-user vs system scope made deliberate (current root cache location contradicts CLAUDE.md).
- lablib.sh and lablib.js duplicate the same output helpers with drifting formats (`ntc` tag mismatch); one canonical logger spec (prefix, colors, stderr policy, log file) implemented once per language, or bash shimming to the JS core.
- `run`/`exif`/`eyif` error semantics are subtle and partially broken; v4 should make "run and report" a single function with explicit exit-code capture, and make hook failure policy (abort vs warn) explicit per hook.
- `exec-function` is the bash→JS bridge (lablib.js), and datastore verbs are special-cased in core dispatch; in v4 the datastore is a natural first .mjs citizen and the special-casing disappears into ordinary commands with an auth layer (fixing the precedence hole by construction).
- Core hard-codes knowledge of specific modules (containers/host-conf.js, srvctl/completion.sh, datastore verbs, `set_permissions` vars) — a v4 module contract should express these as capabilities (provides-config-generator, provides-completion, provides-kv-store) instead.
- Dead/dev material to relocate or drop: root `server.js` (dead), `push.sh` (hardcoded /srv/codepad-project paths, replaced by git workflow), `claude.sh`, `encode.mjs` → `tools/`; `/bin/pop` auto-exec and the per-run sudo symlink creation belong in an explicit `install`/`doctor` command, not in every startup.
- `example-conf` vs gitignored `live-conf` (real production IPs/branding in the working tree) suggests v4 needs a clean config-templating story with deployment data strictly outside the source tree.
- Duplicated systemd unit-type matching loops in `modules/srvctl/command.sh:52-81` (system vs user, identical 11-suffix lists) and the twin default-command mechanism are candidates for one table-driven resolver.
