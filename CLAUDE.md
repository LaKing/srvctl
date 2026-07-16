# CLAUDE.md - srvctl

## Project Overview

srvctl (v3) is a container farm manager for microsite hosting on Fedora servers. It uses **systemd-nspawn** containers and is written in **bash** and **JavaScript/Node.js**. 
The CLI is invoked as `srvctl` or `sc`.
srvctl is deployed across many production servers

## Repository Layout

```
srvctl.sh          # Main entry point
init.sh            # Initialization, module loading, config sourcing
commonlib.sh       # Core functions (hint, load_libs, run_hook, etc.)
lablib.sh          # Color output and utility functions
version            # Current version string
modules/           # 37 plugin modules (see below)
```

Configuration templates are inline in `documentation/documentation.md`
(Initial Configuration); the shipped `example-conf/` was removed in 4.0.0.7.

## Module Structure

Each module under `modules/<name>/` follows this pattern:

```
module-condition.sh   # Determines if module is active (sourced at init)
commands/*.sh         # CLI commands exposed to users
hooks/*.sh            # Lifecycle hooks (pre-init, init, post-init, regenerate, etc.)
libs/*.sh             # Library functions sourced when module is enabled
conf/                 # Configuration templates
```

Modules are enabled/disabled based on `module-condition.sh` checks. State is cached in `~/.srvctl/modules.conf` (including root), keyed to the canonical cluster-config SHA-256; `/var/local/srvctl/modules.conf` is a generation-checked legacy fallback.

## Command Documentation Format

Commands use structured comments for help text:

```bash
## @@@ command-name [ARGS]    # Optional: command syntax
## @en English hint            # Mandatory: single-line hint
## &en English help line       # Mandatory: multi-line help (repeatable)
## &&& dynamic-command         # Optional: dynamic help output
## @hu Hungarian hint          # Optional: translation
```

## Key Conventions

- **Variables**: Uppercase with `SC_` prefix (e.g., `SC_HOSTNET`, `SC_DATASTORE_RW_DIR`). Often `readonly`.
- **Functions**: Lowercase with underscores (e.g., `run_hook`, `load_libs`).
- **Commands**: Lowercase with hyphens (e.g., `add-ve`, `backup-ve`).
- **Output helpers**: `msg` (info), `ntc` (notice/yellow), `prg` (progress/green), `err` (error/red), `debug`/`dbg` (debug).
- **Error helpers**: `exif` (exit if failed), `eyif` (warn if failed).
- **Auth helpers**: `authorize`, `argument container-name`, `sudomize`.
- Guard scripts with `[[ $SRVCTL ]] || exit 10` at the top.
- ShellCheck compliance is expected (`# shellcheck disable=SCXXXX` for intentional exceptions).

## Execution Flow

1. `srvctl.sh` sources `init.sh`
2. `init.sh` sources `/etc/srvctl/*.conf`, tests module conditions, runs hooks
3. Command dispatch: root custom commands -> module commands -> user custom commands -> module defaults
4. Hook execution order: `pre-$CMD` -> `$CMD` -> `post-$CMD`

## Build and Run

No build step. Install by cloning to `/usr/local/share/srvctl` and running `bash srvctl/srvctl.sh` as root, which creates `/bin/sc` and `/bin/srvctl` symlinks.

## Configuration Locations

- `/etc/srvctl/` - Static config (JSON and `.conf` files; `clusters.json` is the canonical topology)
- `/var/srvctl3/host/` - Generated per-host projections of the topology (`host.conf`, `hosts.json`); never edit
- `/var/srvctl3/datastore/` - Read-write data store
- `/srv/` - Container root filesystems and mounts

## Networking

Uses class A `10.x.x.x` network. Each host has a unique HOSTNET ID (16-255). OpenVPN mesh connects cluster hosts via `10.15.x.y`.
