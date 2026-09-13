# CLAUDE.md - srvctl

## Project Overview

srvctl (v4 — the `version` file says `4.0.0.8`, branch `v4`) is a container farm manager for microsite hosting on Fedora servers. It uses **systemd-nspawn** containers and is written in **bash** and **JavaScript/Node.js**.
The CLI is invoked as `srvctl` or `sc`; both are symlinks to `srvctl.sh`.
srvctl is deployed across many production servers.

## Repository Layout

```
srvctl.sh          # Entry point: argv -> CMD/ARG/ARGS/OPA/OPAS, SC_MODULES, dispatch
init.sh            # Initialization, module loading, config sourcing, init hooks
commonlib.sh       # Core functions (hint, load_libs, run_hook/run_hooks, run_command)
lablib.sh          # Color output and utility functions (msg/ntc/err/exif/run/...)
lablib.js          # Node.js counterpart of lablib.sh (msg/ntc/err/get)
server.js          # Inert root stub ("// there is no spoon."); real servers are in modules/
version            # Current version string (4.0.0.8)
modules/           # 37 plugin modules (see below)
documentation/     # documentation.md and hints.txt
update-campaign/   # v4 rework notes and work packages; notes, not shipped code
push.sh            # Dev-only git commit+push helper, NOT a srvctl command
production/        # Local live-config sandbox, gitignored and not part of the repo
```

Configuration templates are inline in `documentation/documentation.md`
(Initial Configuration); the shipped `example-conf/` was removed in 4.0.0.7.

## Module Structure

Each module under `modules/<name>/` follows this pattern:

```
module-condition.sh   # Decides if the module is active; must print "true" on stdout
command.sh            # Optional per-module fallback command (only containers, srvctl)
commands/*.sh         # CLI commands exposed to users (38 files across all modules)
hooks/*.sh            # Lifecycle hooks (84 files; see hook names below)
libs/*.sh             # Bash libraries, sourced by load_libs when the module is enabled
lib/*.mjs, *.js       # Node.js libraries (containers, datastore, named, srvctl only)
selftest/             # *.test.sh / *.test.mjs (certificates, containers, datastore,
                      #   named, srvctl only)
conf/                 # Configuration templates (only containers, perdition,
                      #   postfix, saslauthd)
```

`SC_MODULES` is assembled in `srvctl.sh:69-88`: root-defined custom modules from
`/root/srvctl-includes/modules/*` first, then the shipped `modules/*`. That order
decides hook and command precedence.

Hook basenames actually shipped: `pre-init`, `init`, `post-init`, `regenerate`,
`regenerate_certificates`, `regenerate_rootfs`, `update-install-host`,
`pre-update-install-host`, `update-install-ve`, `firewalld`, `diagnose`,
`adjust-service`, `mkrootfs_fedora`, `add_ve_codepad`, `version`. Several dispatch
points are fired but have no handler in any shipped module — `add-ve`,
`mkrootfs_debian`, `pre-init-$CMD`, `post-init-$CMD` — they exist purely as
extension points for custom modules.

Modules are enabled/disabled based on `module-condition.sh` checks. State is cached in `~/.srvctl/modules.conf` (including root), keyed to the canonical cluster-config SHA-256; `/var/local/srvctl/modules.conf` is a generation-checked legacy fallback.

## Command Documentation Format

Commands use structured comments for help text:

```bash
## @@@ command-name [ARGS]    # Optional: syntax override; first match in the whole file
## @en English hint           # Mandatory: single-line hint, MUST be in the first 10 lines
## &en English help line      # Mandatory: multi-line help (repeatable, whole file)
## &&& dynamic-command        # Optional: executed, its output appended to the help
```

Those four are the only markers. They are defined once as `HEMP`/`HINT`/`HELP`/`HEXE`
in `commonlib.sh:17-23` and mirrored in `modules/srvctl/lib/commandindex.mjs:20-23`.
Values are sliced with `${line:7}` (6 marker chars + 1 space), so use exactly one
space after the marker. `hint_on_file` reads `@en`, `@@@` and `&&&`; `help_on_file`
reads `@en` and `&en` — neither reads all four.

There is **no translation support anywhere in the codebase**: nothing reads
`## @hu` / `## &hu`, and no language is ever selected. The markers survive in one
file only, `modules/containers/commands/add-ve.sh:9-11`, as inert comments.

Line-anchored guard calls (`root_only`, `operators_only`, `reseller_only`, `hs_only`)
double as visibility markers: `hint_on_file` lists only what the caller's role could
actually run (`commonlib.sh:234-238`). `owner_only` is resource-scoped, so it stays
listed for everyone.

## Key Conventions

- **Variables**: Uppercase with `SC_` prefix (e.g., `SC_HOSTNET`, `SC_DATASTORE_RW_DIR`). Often `readonly`.
- **Functions**: Lowercase with underscores (e.g., `run_hook`, `load_libs`).
- **Commands**: Lowercase with hyphens (e.g., `add-ve`, `backup-ve`).
- **Output helpers** (`lablib.sh`): `msg` (host-prefixed green), `ntc` (host-prefixed yellow), `prg` / `pry` (plain green / yellow), `err` (red, to stderr **and** `$SC_LOG`), `log` / `logs` / `logfs` (log file), `debug` / `dbg` / `trace` (printed only when `$DEBUG` **and** `$SC_TTY`), `run` / `nur` (echo a prompt-style command line, then execute it).
- **Error helpers**: `exif` (exit if the previous command failed), `eyif` (warn if failed), `exit_0` (clean exit).
- **Auth helpers** (`modules/srvctl/libs/authlib.sh`, always loaded, host- and VE-side): `sc_is_root`, `sc_role`, `root_only`, `operators_only`, `owner_only <type> <id>`, `reseller_only`, `argument <name>`, `sudomize` (non-root re-exec via sudo). The exit codes are a contract callers rely on: **44** = authorization failure, **32** = missing argument. Guards must be called *before* any state change.
  - Root means `sc_is_root`: `SC_USER == root` **and** uid 0. Plain uid 0 is not enough — the NOPASSWD sudoers entry lets any user reach uid 0 with `SC_USER` still their own name.
  - `authorize` still exists but is an inert **stub** (`authlib.sh:151-165`): a non-root caller only gets `DEV (Authorization implementation not complete.)` printed and execution *continues*. It denies nothing; do not use it as a gate.
  - `hs_only` / `ve_only` are also **inert** (`authlib.sh:204-228`): `SC_ON_HS` / `SC_ON_VE` are never assigned, so `if $SC_ON_HS` runs an empty command (status 0) and both always pass. Real host/VE separation comes from module-activation conditions plus `root_only`.
- **Guard**: files that must not run standalone start with `[[ $SRVCTL ]] || exit <n>`, but the code is **not** consistent about `<n>`. 26 occurrences use `exit 4` (20 shipped commands/hooks plus 6 selftest auth fixtures); 6 use `exit 10` (`commonlib.sh:13`, `modules/certificates/libs/certselectlib.sh:27` and the four fixture command files under `modules/srvctl/selftest/sandbox/fixture-modules/` — two modules, `harnessa` and `harnessb`, with two commands each). Use `exit 4` in new commands and hooks. Only 17 of the 38 `modules/*/commands/*.sh` carry the guard at all — several unguarded files carry a `FIXME(v4)` about it (e.g. `modules/ve/commands/status.sh:11`, whose comment still calls `exit 10` "standard"). Put the guard *after* the `## @en` block so the hint stays inside the first 10 lines.
- ShellCheck compliance is expected (`# shellcheck disable=SCXXXX` for intentional exceptions).

## Execution Flow

1. `srvctl.sh` parses argv into `CMD`/`ARG`/`ARGS`/`OPA`/`OPAS`, builds `SC_MODULES`, sets `SRVCTL="srvctl-$(cat version)"`, then sources `init.sh` (aborting with exit 1 if that fails).
2. `init.sh`: `/etc/srvctl/debug.conf` -> `/bin/sc`, `/bin/srvctl` and bash-completion symlinks -> `lablib.sh` + `commonlib.sh` -> regenerate host-local config from the canonical `/etc/srvctl/clusters.json` -> source every `/etc/srvctl/*.conf`, then the generated `/var/srvctl3/host/host.conf` -> resolve `SC_USER`/`SC_UID0`/`SC_HOME` -> `test_srvctl_modules`.
3. Init hook order (`init.sh:303-327`), which is **not** a `pre`/`main`/`post` triplet and does not load libs last:
   `pre-init-$CMD` -> `pre-init` -> (breakout: `man`, `help`, `-help`, `--help` print help and exit here) -> `load_libs` -> `init` -> `post-init` -> `post-init-$CMD`.
   So module libs are available in `init` and `post-init` hooks but **not** in `pre-init` hooks, and for `sc help` the `init`/`post-init` hooks never run.
4. Command dispatch (`run_command`, `commonlib.sh:122`) — first match wins, everything sourced into the current shell: `exec-function` (genuine root + `OPAS` only) -> datastore write verbs `new|put|cfg|del|add` (genuine root) -> datastore read verbs `get|out` (any caller) -> `/root/srvctl-includes/$CMD.sh` -> `modules/*/commands/$CMD.sh` in `SC_MODULES` order -> `$SC_HOME/srvctl-includes/$CMD.sh` (non-root only) -> every enabled module's `command.sh` fallback. Returns **54** when no command was given, **250** when nothing matched; `srvctl.sh` then prints `Invalid command` and the hint list, and exits 1.
5. `run_hook <name>` sources `hooks/<name>.sh` of every enabled module **once**, in `SC_MODULES` order; a hook that exits non-zero aborts the whole CLI through `exif`. `run_hooks <name>` is the separate wrapper that fires the `pre-<name>` -> `<name>` -> `post-<name>` triplet — used for `update-install-host`, `update-install-ve`, `firewalld`, `diagnose`, `mkrootfs_fedora`, `mkrootfs_debian` and `add_ve_create_nspawn_container`. There is no `pre-$CMD` / `$CMD` / `post-$CMD` triplet anywhere.

## Build and Run

No build step and no package manifest. Install by cloning to `/usr/local/share/srvctl` and running `bash srvctl/srvctl.sh` as root; `init.sh:32-62` then creates the `/bin/sc` and `/bin/srvctl` symlinks and, when `/etc/bash_completion.d` exists, `srvctl-completion`. All three point back into the clone, so upgrading is a `git pull` (`sc update-install`).

Tests: no CI and no top-level runner. Per-module selftests live in `modules/*/selftest/` (27 `*.test.sh` / `*.test.mjs` files under certificates, containers, datastore, named and srvctl). `modules/datastore/selftest/run.sh` and `modules/named/selftest/run.sh` aggregate their own module's tests and return non-zero on any failure; the rest are run directly with `bash <file>` or `node <file>`.

## Configuration Locations

- `/etc/srvctl/` - Static config (JSON and `.conf` files; `clusters.json` is the canonical topology). `debug.conf` is sourced first, before anything else in `init.sh`
- `/var/srvctl3/host/` - Generated per-host projections of the topology (`host.conf`, `hosts.json`); never edit
- `/var/srvctl3/datastore/` - Read-write data store (`SC_DATASTORE_RW_DIR` default)
- `/var/srvctl3/gluster/srvctl-data/` - Read-only cluster datastore (`SC_DATASTORE_RO_DIR` default); `SC_DATASTORE_DIR` starts out pointing here
- `/var/srvctl3/share/` - Host-side shared state; `containers/<C>` and `common/` are bind-mounted read-only into each container (`modules/datastore/lib/generators.mjs:158-159`). `lock/` is created by the containers update-install hook but is NOT bind-mounted — its `BindReadOnly` line is commented out (`modules/datastore/lib.js:715`)
- `/srv/` - Container root filesystems and mounts
- `~/.srvctl/` - Per-user state: the `modules.conf` cache and `srvctl.log` (`$SC_LOG`)
- `/root/srvctl-includes/` - Root's custom `$CMD.sh` commands and custom `modules/`, both ahead of the shipped ones; `$SC_HOME/srvctl-includes/` is the non-root equivalent, consulted *after* module commands

## Networking

Uses class A `10.x.x.x` network. Each host has a unique HOSTNET ID, conventionally 16-255 — that range is a convention only, nothing in the code validates it. Container IPs are `10.<hostnet>.<user_id>.<offset>`, with the bridge host address at `10.<hostnet>.<user_id>.1`. The OpenVPN mesh connects cluster hosts via `10.15.x.y` (x = server hostnet, y = client hostnet) over UDP 1101. That `10.15` prefix is hardcoded in `modules/openvpn/libs/openvpnconfiglib.sh` and `modules/datastore/lib/generators.mjs:260-262`, where a `FIXME(v4)` notes it is meant to become `10.16` under the zerotier work.
