# ve — v3 fact sheet (commit 988c38c)

## Purpose
Marks the "we are running INSIDE a container" side of srvctl (VE = virtual environment). It is the counterpart of the `containers` module (host side): it detects container virtualization, provides a minimal in-container `status` command, and sets a couple of environment defaults via its pre-init hook. Its `module-condition.sh` doubles as the shared "am I in a container?" oracle sourced by other modules (`usersonve`). Three files total; essentially untouched since 2017 (pre-init.sh last touched 2020-09).

## Activation
`modules/ve/module-condition.sh` — sourced in a command-substitution subshell by `test_srvctl_modules` (commonlib.sh:436), result cached as `export SC_USE_VE=true|false` in `/var/local/srvctl/modules.conf` (root) / `~/.srvctl/modules.conf` (user).

Logic (module-condition.sh:3-12):
- `SC_VIRT=$(systemd-detect-virt -c)` (container-only detection)
- `true` if `$SC_VIRT == systemd-nspawn` or `$SC_VIRT == lxc` (comment: "lxc is deprecated, but we can consider it a container ofc.")
- `false` otherwise.

So the module is enabled exactly when srvctl runs inside an nspawn or lxc container. Mutually exclusive with `containers` in practice: containers/module-condition.sh:15-19 returns false inside nspawn/lxc — EXCEPT the `update-install <arg>` escape hatch (containers/module-condition.sh:28-32) which can make both true during an in-container `sc update-install <arg>` run and persist that in modules.conf (containers-module concern, but it shadows ve's `status`, see Bugs).

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| `status` (commands/status.sh) | `List container status parameters` | `msg "$HOSTNAME running."`; `msg "connected users:"`; runs `w`; `msg "Disk usage:"`; runs `du -hs /home`, `du -hs /srv`, `du -hs /var` | read-only (utmp read, directory traversal); no authorize/argument gate — visible and runnable by every user on the VE. Reachable also via alias `sc ?` (srvctl.sh:92 maps `?` → `status`). |

On hosts (SC_USE_VE=false, SC_USE_CONTAINERS=true) the same command name is served by `modules/containers/commands/status.sh`; dispatch is first-match over `SC_MODULES` glob order (commonlib.sh:150-168, srvctl.sh:72-75) where `containers` sorts before `ve`.

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| hooks/pre-init.sh | `run_hook pre-init` (init.sh:164), sourced into the MAIN shell on every srvctl invocation inside a VE | line 4: `readonly SC_VIRT=$(systemd-detect-virt -c)` (main-shell readonly; no other main-shell consumer exists — effectively dead). line 9: `[[ $SC_ROOTFS_DIR ]] \|\| SC_ROOTFS_DIR=/var/srvctl3/rootfs`. line 12: `[[ $SC_MOUNTS_DIR ]] \|\| SC_MOUNTS_DIR=/var/srvctl3/mounts`. Both defaults are verbatim duplicates of containers/hooks/pre-init.sh:4,7; inside a VE they are consumed only by `set_permissions` (commonlib.sh:494-495, `-d`-guarded, so normally no-ops). |

## Libs
`modules/ve/libs/` exists but is EMPTY (harmless: `load_libs` guards with `[[ -f $sourcefile ]]`, commonlib.sh:62). No functions provided.

Consumed BY other modules: `modules/usersonve/module-condition.sh:3` sources `$SC_INSTALL_DIR/modules/ve/module-condition.sh` verbatim as its own condition — the file's path, source-ability (it uses `return`), and its `true`/`false` stdout contract are a cross-module API.

## Config & templates
- (no `conf/` directory, no templates)

## State touched
- Reads: virtualization state via `systemd-detect-virt -c`; utmp (`w`); sizes of `/home`, `/srv`, `/var` (`du -hs`).
- Writes: none by the module itself. Enablement flag `SC_USE_VE` is cached by core in `/var/local/srvctl/modules.conf` and `$HOME/.srvctl/modules.conf` (commonlib.sh:448).
- Shell env (main shell, VE only): `SC_VIRT` (readonly, unexported), `SC_ROOTFS_DIR`, `SC_MOUNTS_DIR` defaults.
- No systemd units, no network, no datastore keys.

## Dependencies
- Core helpers: `msg` (lablib.sh:23), sourcing model of `test_srvctl_modules` / `run_hook` / `run_command` (commonlib.sh:436, 103, 164), `exif` post-command check (commonlib.sh:165), hint parser `## @en` (commonlib.sh:229).
- External binaries: `systemd-detect-virt` (systemd), `w` (procps-ng), `du` (coreutils).
- Other modules: none required at runtime; `usersonve` depends on this module's condition file; `containers` provides the competing `status` command on hosts; `firewalld`, `codepad`, `gui`, `gluster`, `containers` each re-implement the same nspawn/lxc detection independently.

## Bugs & smells
- **medium** modules/ve/commands/status.sh:9-11 — `du -hs /home; du -hs /srv; du -hs /var` run unguarded as the command body; for any non-root user (permission-denied subdirs like `/var/lib/private`, other users' 700 homes) `du` exits 1 as the script's last command, so `run_command`'s `exif "'$CMD' failed ($dir)"` (commonlib.sh:165) fires: `sc status` / `sc ?` prints du permission errors, then a red `'status' failed (...)`, and srvctl exits 1 even though the command did its job. Sizes shown are also silently undercounted for non-root.
- **low** modules/ve/commands/status.sh:3 — only a `## @en` hint, no mandatory `## &en` help lines (CLAUDE.md format contract), so `sc help status` renders an empty help body (help_on_file greps `## &en`, commonlib.sh:329).
- **low** modules/ve/hooks/pre-init.sh:4 — `readonly SC_VIRT=$(systemd-detect-virt -c)` in the main shell is dead code: no main-shell consumer of `SC_VIRT` exists anywhere (all other uses are inside condition subshells), it forks a process on every srvctl invocation in a VE, the `readonly VAR=$(cmd)` form masks the command's exit status, and the readonly mark will make any future `SC_VIRT` assignment in the same shell (e.g. from an `/etc/srvctl/*.conf`) error out.
- **low** modules/ve/commands/status.sh:1, modules/ve/hooks/pre-init.sh:1 — missing `[[ $SRVCTL ]] || exit 10` guard required by convention (CLAUDE.md); executing status.sh directly runs `w`/`du` outside srvctl. Shared smell — several other modules' pre-init hooks lack it too (branding, containers, datastore, openvpn).
- **smell** modules/ve/commands/status.sh:5 — hint says "List container status parameters" but the body prints hostname/users/disk of the *current* VE; wording collides with containers' `status` ("List container statuses"), which shadows it whenever `SC_USE_CONTAINERS=true` leaks to true inside a VE (containers/module-condition.sh:28-32 during `update-install <arg>`), silently swapping command semantics.

## Polish risks
- `modules/ve/module-condition.sh` path and behavior are a cross-module API: sourced by `modules/usersonve/module-condition.sh:3` inside `$( source ... )`; it must stay source-able (top-level `return`, module-condition.sh:9) and print exactly `true` or `false` as its ONLY stdout (compared `== true` at commonlib.sh:437-442). Any extra stdout breaks both ve and usersonve enablement.
- Module directory name `ve` is load-bearing: it derives the persisted flag name `SC_USE_VE` (`"SC_USE_${module^^}"`, commonlib.sh:431) written as `export SC_USE_VE=...` into modules.conf (commonlib.sh:448); existing servers have this cached.
- lxc must remain accepted as container (module-condition.sh:6) — deployed lxc guests exist per the comment.
- Command name `status` and the `sc ?` alias (srvctl.sh:92) must keep resolving to this file on VEs; on hosts `containers` must keep winning first-match dispatch (alphabetical `SC_MODULES` glob, srvctl.sh:72-75).
- Exact output sequence of `status` (status.sh:5-11): `msg "$HOSTNAME running."` (full hostname in text, `[ ${HOSTNAME%%.*} ]` blue prefix per lablib.sh:23-26), `msg "connected users:"`, raw `w` output, `msg "Disk usage:"`, three raw `du -hs` lines in order /home, /srv, /var. Hint string `List container status parameters` (status.sh:3) appears in `sc help`/completion.
- Env default values and precedence (pre-init.sh:9,12): `SC_ROOTFS_DIR=/var/srvctl3/rootfs`, `SC_MOUNTS_DIR=/var/srvctl3/mounts`, only when unset — `/etc/srvctl/*.conf` values (sourced earlier, init.sh:110-116) must keep winning.
- `SC_VIRT` becomes readonly in the main shell on VEs (pre-init.sh:4); a rewrite must not add a later `SC_VIRT=` assignment in the same shell, or it will die with "readonly variable".

## v4 notes
- Centralize container detection: the nspawn/lxc test is copy-pasted in 6 condition files (ve, containers:12-19, firewalld:9-12, codepad:3-11, gui:3-9, gluster:14-21). One core `is_container()` / a single `SC_ON_VE` boolean computed in init would replace all of them — note `ve_only`/`hs_only` in containers/libs/authlib.sh:13-21 already *expect* `SC_ON_VE`/`SC_ON_HS`, which are never assigned anywhere today (bug belonging to containers/usersonve sheets).
- Fold `usersonve` into `ve` (usersonve's condition is literally "source ve's condition"); one VE-side module.
- Drop the dead `readonly SC_VIRT` main-shell export; drop the duplicated SC_ROOTFS_DIR/SC_MOUNTS_DIR defaults from the VE side (they describe host paths) or move both defaults into core config.
- `status` as .mjs: gather uptime/users/disk in one place, `du -hs /home /srv /var` in a single invocation with stderr suppressed and exit code normalized, or use statfs; unify hint/help text with containers' host-side status.
- Empty `libs/` dir can be deleted.
