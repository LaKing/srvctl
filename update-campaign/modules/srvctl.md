# srvctl (self) — v3 fact sheet (commit 988c38c)

## Purpose
The `srvctl` module is srvctl's self-management module and, in practice, part of the core:
it owns the **update/install flow** (`update-install`), the `version` and `diagnose`
commands, custom-command authoring (`customize`), the bash **command-completion**
system (completion.sh + completionlib), and the **default command** (`command.sh`) that
turns `sc SERVICE start|stop|status|…` into systemctl operations. Its `libs/` provide
authorization primitives (`root_only`, `argument`, `authorize`, `sudomize`), dnf wrappers
(`sc_install`, `sc_update`), systemd service registration (`add_service`, `rm_service`),
systemd-networkd host configuration, and the per-invocation root command log hook.
Because virtually every other module calls these functions, this module is de-facto
mandatory core, not an optional plugin.

### The self-update flow (precise, for the v4 rollout)
`sc update-install [HOSTNAME]` (root only, `commands/update-install.sh`):

1. **Before dispatch, in init.sh** (`init.sh:63-106`, triggered by `CMD == update-install`):
   ensures `nodejs` and `git` are installed (`dnf -y install`), deletes
   `/var/local/srvctl/modules.conf`, regenerates `/etc/srvctl/clusters.json`,
   `/etc/srvctl/host.conf`, `/etc/srvctl/hosts.json` from `/etc/srvctl/data/` via
   `modules/containers/host-conf.js`, and copies every `/etc/srvctl/data/*.conf` to
   `/etc/srvctl/`. Then `test_srvctl_modules` (`commonlib.sh:404-479`) re-evaluates every
   `module-condition.sh` and **appends** the `export SC_USE_X=…` lines to the conf file
   (`/root/.srvctl/modules.conf` for root, since `SC_HOME` is set — the
   `/var/local/srvctl/modules.conf` deleted at init.sh:84 is *not* the file appended to,
   so the root conf grows on every run; later lines win on re-source, so behavior stays
   correct).
2. `root_only` (`update-install.sh:8`), then `sc_update` = `dnf -y --releasever
   $VERSION_ID update` — full OS package update, unconditionally, *before* any argument
   check (`update-install.sh:10`, `libs/fedoralib.sh:14-18`).
3. **Container branch**: if `! $SC_USE_CONTAINERS` (i.e. running *inside* a VE), runs
   `run_hooks update-install-ve` (only `modules/firewalld` ships that hook), prints
   `"$HOSTNAME update-install complete"`, `exit 0` (`update-install.sh:12-19`).
4. **Host branch**: without `ARG` prints `"No argument, so we will stop here."` and exits 0
   (`update-install.sh:22-28`) — so the dnf update still happened. With `ARG`:
   - writes `DEBUG=true` to `/etc/srvctl/debug.conf` if absent (`:30-34`),
   - overwrites `/etc/selinux/config` with the single line `SELINUX=disabled` (`:37-38`),
   - installs `mc`, `nodejs`, `git` if missing (`:42-44`),
   - if `HOSTNAME == localhost.localdomain`: writes `$ARG` to `/etc/hostname`, removes
     `/var/local/srvctl/modules.conf`, and **exits 5** (reboot required) (`:47-64`),
   - sets git global user.name=srvctl / user.email=srvctl@$HOSTNAME (`:67-68`),
   - `ssh-keyscan`s every `get cluster host_list` host into `~/.ssh/known_hosts` (`:70-80`),
   - `run_hooks update-install-host` → `pre-update-install-host` (containers module:
     `networkd_configuration` from this module's `libs/networkdlib.sh` — may disable
     NetworkManager and rewrite `/etc/systemd/network/*.network`), then every active
     module's `update-install-host.sh`, then `post-…` (`:83`),
   - if `$SC_USE_GUI`: `make_commands_spec` (gui module lib) (`:85-88`),
   - `cat modules/srvctl/completion.sh > /etc/bash_completion.d/srvctl-completion` (`:91`)
     — see Bugs: on a standard install this path is a symlink back to the source file,
   - `set_permissions` (commonlib) and `"update-install complete. please reboot."` (`:94-96`).

**Note:** update-install does *not* update the srvctl code itself. There is no `git pull`
anywhere in the flow. Code delivery is out-of-band: the bootstrap script
(`example-conf/pop.sh`) clones the repo to `/usr/local/share/srvctl`, and on dev boxes a
`/bin/pop` script (if present) is executed at *every* root+tty srvctl invocation
(`srvctl.sh:27-31`, "REALLY only for development"). A v4 rollout riding "self-update"
therefore means: get new code onto the box by whatever `/bin/pop` or manual git pull does,
then run `sc update-install HOSTNAME` to re-test modules, re-run all install hooks, and
regenerate completion/spec data.

## Activation  (module-condition.sh logic — when is this module enabled)
`module-condition.sh` is `echo true` — the module is **always enabled**, for every user,
host or container (`modules/srvctl/module-condition.sh:2`). `SC_USE_SRVCTL=true` always.

## Commands
| command | hint (`## @en`) | behavior | side effects |
|---|---|---|---|
| `update-install [HOSTNAME]` | "Run the installation/update script." | See "self-update flow" above. `root_only`. | dnf update of the whole OS; SELinux disabled; `/etc/srvctl/debug.conf`; `/etc/hostname`; git global config; `~/.ssh/known_hosts` append; all modules' install hooks; `/etc/bash_completion.d/srvctl-completion`; `set_permissions`; exit 5 on first-hostname path |
| `version` | "List software versions installed." | prints `-- software-versions --` then `msg_version_installed postfix` and `nodejs` (dnf info) | none |
| `diagnose` | "First-aid diagnoistic command." (note the typo — preserved output) | prints srvctl version (`cat $SC_INSTALL_DIR/version`), `diagnose_variables` (set-grep of DEBUG/ARG/CMD/OPA/SC_/USER/HOST vars), uptime, `uname -a`, `sestatus`, memory, disks, grub boot entries, per-unit status of `/etc/systemd/system/multi-user.target.wants/*`, failed units, postfix fatals + `postqueue -p`, firewalld zone/services/interfaces, `top -n 1`, `w`, then `run_hooks diagnose` (containers, datastore, firewalld, gluster, haproxy modules ship diagnose hooks), then postqueue hints | read-only (runs many status commands) |
| `customize COMMAND` | "Create/edit a custom command." | exit 23 if no ARG; lowercases name; backs up existing `$SC_HOME/srvctl-includes/$arg.sh` to `$SC_HOME/.srvctl/srvctl-includes.bak/$arg-$NOW.sh`; else creates it from template (or from `$SC_INSTALL_DIR/commands/$arg.sh` — dead path, that dir does not exist); opens `mcedit`; beautifies with vendored `apps/beautify_bash.py` if `/bin/python`; runs shellcheck if present; regenerates completion in background | creates/edits files under `$SC_HOME/srvctl-includes/`; writes completion data |
| `fix-owner` | "Set user and group on all content to parent owner." | **no-op** — the only action line is commented out (`fix-owner.sh:8`) | none (contrary to its help) |
| `fix-sshd` | "Fixing sshd permissions on keyfiles." | chown root:ssh_keys + chmod 600 on the three `/etc/ssh/ssh_host_*_key` files, restart sshd | modifies host ssh keys perms, restarts sshd.service |
| `ls` | "List all files recursive, sorted by last modified date" | `run 'find . -type f -exec ls -lt {} +'` in `$PWD` | none |
| *(default)* `command.sh` — `SERVICE OP \| OP SERVICE` | "OP is one of status\|start\|stop\|kill\|restart\|enable\|remove, SERVICE is a systemd service" | Runs when no named command matched. Normalizes op/service order (op list: enable start restart stop status disable kill; `? + - !` already mapped in srvctl.sh:92-100); `run_hook adjust-service` (containers/openvpn modules may rewrite `$service`); if `systemctl is-active` fails, scans system unit dirs (`/usr/lib/systemd/system`, `/etc/systemd/system{,/*}`, `/run/systemd/{system,transient}`) then user unit dirs (`~/.config/systemd/user`, `/etc/systemd/user`, `$XDG_RUNTIME_DIR/systemd/user`, `/run/systemd/user`, `~/.local/share/systemd/user`, `/usr/lib/systemd/user`) for `$service.{service,socket,device,mount,automount,swap,target,path,timer,slice,scope}`, printing `ASSUME system-service:`/`ASSUME user-service:` and setting `--user` for the latter; then `service_action` and `exit_0`; if not found, `return 0` (dispatcher continues → "Invalid command.") | systemctl enable/restart/stop/kill (see Libs: service_action); **always exits 0** once a unit was matched, even on failure |

The `## spec //services×start×…` lines in `command.sh:18-22` are harvested by the gui
module (`modules/gui/libs/spec.sh:59`) into `/var/local/srvctl/commands.spec`.

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/post-init.sh` | post-init (every invocation) | appends `"$NOW [$SC_USER@$HOSTNAME $(pwd)]# $0 $*"` to `$SC_LOG` (`~/.srvctl/srvctl.log`) — duplicate of init.sh:140 `logs` line and (for root) `/var/log/srvctl-root.log` |

## Libs
All loaded for every invocation (module always active). Heavy external use (call-site scan):

- `libs/authlib.sh` — `root_only` (exit 44; **echoes `SC_UID0 true` to stdout**), `reseller_only`
  (single-char username or root, exit 44), `argument` (exit 32 if `$ARG` empty), `authorize`
  (root passes; otherwise only prints "DEV (Authorization implementation not complete.)" and
  **continues** — no exit), `sudomize` (non-root re-exec: `run sudo $SC_INSTALL_DIR/srvctl.sh
  $SC_COMMAND_ARGUMENTS`, exits on success; failure exit code is masked to 0 — see Bugs).
  Used by containers, usersonhost, usersonve, codepad, haproxy, named, saslauthd, gui,
  wordpress, odoo, … (≈60 call sites). **This is srvctl's entire permission model.**
- `libs/adjust-servicelib.sh` — `service_action SERVICE OP [XSWITCH]`: `status` → `systemctl
  status -n 30`; empty OP → `journalctl -u SERVICE --since yesterday`; `start|restart|enable`
  → `systemctl enable` + `restart` + status; `kill` → kill + status; `stop|disable` →
  (disable if OP=disable) + stop + status; requires root, `--user`, or wheel-group
  membership else err + return 66; unknown op → return 223. Also used by
  containers/status.sh, containers/update-ve.sh, openvpn adjust-service hook.
- `libs/fedoralib.sh` — guarded by `[ "$ID" == fedora ] || return`. `sc_install` (`dnf -y -q
  install`, used by ~20 modules), `sc_update` (`dnf -y --releasever $VERSION_ID update`),
  `msg_version_installed` (dnf info; used by named/postfix/perdition/opendkim version
  hooks), plus an older copy of `add_service`/`rm_service`.
- `libs/systemdlib.sh` — `add_service NAME` (symlink unit into `/etc/srvctl/system/`,
  enable+restart+status; used by postfix, mariadb, named, opendkim, perdition, nfs,
  saslauthd, wordpress) and `rm_service NAME` (unused). **Byte-identical duplicates of the
  fedoralib versions**; systemdlib is sourced later (alphabetical) so its copies win.
  Nothing in the repo ever reads `/etc/srvctl/system/` back — it is a write-only registry.
- `libs/completionlib.sh` — `generate_completion [USER]`: (root) `mkdir -p` + **`chmod 777`**
  `/var/local/srvctl/completion`; redefines `complicate()` so that `hint_commands` (run for
  its side effects, output → `$user.hints`) also appends every `## @@@` arg-spec line to
  `$user.arguments` and each command word to `$user.commands` (capitals stripped); writes
  `$user.VE` (`cfg user container_list`) when containers active; collects unit-file
  basenames into `$user.units`. Called from init.sh:188-192 on `sc complicate` and
  backgrounded from customize.sh:63.
- `libs/diagnoselib.sh` — `diagnose_variables` (posix `set` grep).
- `libs/moduleslib.sh` — `reset_modules`: removes `/var/local/srvctl/modules.conf` and
  `/home/*/.srvctl/modules.conf`. **Never called anywhere**, and misses root's actual cache
  `/root/.srvctl/modules.conf`.
- `libs/networkdlib.sh` — `networkd_configure_interface IFACE` (writes
  `/etc/systemd/network/$IFACE.network`, static from datastore `get host …` values for the
  primary interface, DHCP otherwise; skips if file exists) and `networkd_configuration`
  (iterates `firewall-cmd --list-interfaces`, symlinks `/etc/resolv.conf` →
  `/run/systemd/resolve/resolv.conf`, enables systemd-networkd/-resolved, **disables
  NetworkManager**, gates on `ping 8.8.8.8`). Called by
  `modules/containers/hooks/pre-update-install-host.sh` — i.e. part of every host
  update-install.

## Config & templates (conf/ contents and where they get installed)
No `conf/` directory. Two non-lib assets:
- `completion.sh` — installed by symlink at init (`init.sh:36-44`) and by copy at
  update-install (`update-install.sh:91`) to `/etc/bash_completion.d/srvctl-completion`.
  Sourced by every interactive bash: spawns `bash /usr/local/share/srvctl/srvctl.sh
  complicate` in the background (hardcoded path), defines `_fedora_srvctl_options`
  completion for `sc` and `srvctl` fed from `/var/local/srvctl/completion/$SC_USER.*`,
  then `display` **cats the user's `.hints` file to the terminal at every shell start**
  (with a 1s sleep, then `no hints`, if missing).
- `apps/beautify_bash.py` — vendored (Paul Lutus 2011, GPL2) bash reindenter; python3
  compiles it (with SyntaxWarnings); invoked by `customize.sh:61` via `/bin/python`.

## State touched
- Host packages: full `dnf update`; installs mc/nodejs/git (update-install).
- `/etc/selinux/config` (overwritten to `SELINUX=disabled`), `/etc/hostname`,
  `/etc/srvctl/debug.conf`, root's global git config, `~/.ssh/known_hosts` (append).
- `/etc/bash_completion.d/srvctl-completion`; `/var/local/srvctl/completion/$USER.{hints,
  commands,arguments,units,VE}` (dir chmod 777, files 660);
  `/var/local/srvctl/commands.spec` (via gui lib).
- `/etc/srvctl/system/*.service` symlinks (add_service/rm_service registry).
- `/etc/systemd/network/*.network`, `/etc/resolv.conf` symlink; systemd units enabled/
  disabled: arbitrary user-named services, systemd-networkd, systemd-resolved,
  NetworkManager (disabled), sshd (restart in fix-sshd).
- `/var/local/srvctl/modules.conf` and `$SC_HOME/.srvctl/modules.conf` (module cache,
  deleted/appended during update-install), `~/.srvctl/srvctl.log` (post-init hook),
  `/var/log/srvctl-root.log` (core), `$SC_HOME/srvctl-includes/` + `.srvctl/srvctl-includes.bak/`.
- Datastore reads: `get cluster host_list`, `get host $HOSTNAME interface|host_ip|gateway|
  prefix|dns1|dns2`, `cfg user container_list`.
- Network: ssh-keyscan of all cluster hosts; ping 8.8.8.8 during networkd_configuration.

## Dependencies
- Core helpers: `msg ntc err prg debug run nur exif eyif exit_0 hint run_hook run_hooks
  logs set_permissions hint_commands` (commonlib/lablib); `$SC_INSTALL_DIR`, `$SC_USER`,
  `$SC_UID0`, `$SC_HOME`, `$NOW`, `$CMD/$ARG`, `$SC_LOG`, `$ID`/`$VERSION_ID`
  (from `/etc/os-release`, init.sh:118).
- Other modules assumed: **containers** (`SC_USE_CONTAINERS` host/VE switch,
  adjust-service hook, host-conf.js in init), **datastore** (`get`, `cfg`), **gui**
  (`make_commands_spec` when `SC_USE_GUI`), firewalld (`firewall-cmd` in networkdlib,
  update-install-ve hook).
- External binaries: dnf, systemctl, journalctl, git, node, ssh-keyscan, mcedit (mc),
  firewall-cmd, networkctl, ping, grub2-editenv, postqueue, top, w, sestatus, shellcheck
  (optional), /bin/python (optional).
- Conversely, most other modules depend on THIS module's authlib/fedoralib/systemdlib —
  disabling it would break the farm (its condition is hardwired `true`, so it cannot be
  disabled in practice).

## Bugs & smells
- **blocker** `commands/update-install.sh:91` — `cat "$SC_INSTALL_DIR"/modules/srvctl/completion.sh > /etc/bash_completion.d/srvctl-completion`
  writes through the symlink that `init.sh:36-44` creates pointing at
  `/usr/local/share/srvctl/modules/srvctl/completion.sh`. On a standard install
  (`SC_INSTALL_DIR=/usr/local/share/srvctl`) this is `cat X > X`: the redirection truncates
  the target first, leaving the module's own `completion.sh` **empty** (verified: `cat f > f`
  yields a 0-byte file). This destroys completion and dirties the install-dir git tree the
  v4 rollout depends on. On split installs (code in `/srv/srvctl`, symlink to
  `/usr/local/share/...`) it silently overwrites the *other* checkout's source file. Must
  become `rm` + copy, or install to a non-symlinked path.
- **medium** `commands/fix-owner.sh:8` — the command's only action (`chown -R $(stat -c '%U' .)…`)
  is commented out; `sc fix-owner` succeeds silently doing nothing, while its help promises a
  recursive chown — users believe ownership was fixed.
- **medium** `command.sh:58` and `command.sh:74` — `[[ "$ck" == "$i" ]]` compares a basename
  to a full path and is never true (intended `"$ck" == "$service"`), so a unit given with
  its explicit suffix (e.g. `sc foo.timer start` while inactive) is never matched — the
  lookup builds `foo.timer.service` etc. — and the command falls through to
  "Invalid command." with exit 1.
- **medium** `command.sh:89-90` (with `libs/adjust-servicelib.sh:57,60-61`) — after
  `service_action`, `exit_0` runs unconditionally, so failures (non-root/non-wheel err
  return 66, unknown op return 223, systemctl failures) all **exit 0**; automation cannot
  detect a failed `sc SERVICE start`.
- **medium** `commands/version.sh:9-12` — never invokes `run_hook version`; the
  `hooks/version.sh` files shipped by named, postfix, perdition and opendkim are dead code
  (grep: nothing in the repo calls `run_hook version`), so `sc version` reports only
  postfix and nodejs.
- **medium** `libs/completionlib.sh:11` — `chmod 777 /var/local/srvctl/completion` makes the
  directory world-writable: any local user can replace any other user's (including root's)
  `.hints`/`.commands`/`.units` files, whose contents are cat'ed into every interactive
  shell at login and fed to `compgen` (completion.sh:35-37,88).
- **medium** `completion.sh:57-60` — `arr=("$command")` creates a one-element array, so
  `argument=${arr[$length-2]}` is empty for every argument position ≥ 1; per-argument
  completion (`$sc_user.$argument` lists) can never trigger. Also `grep "$CMD"` at :57 is
  an unanchored substring match (e.g. `sc ls <TAB>` greps every line containing "ls").
- **low** `libs/authlib.sh:53-55` — in `sudomize`'s failure branch `exit $?` executes after
  `debug`, which returns 0, so a failed `sudo srvctl.sh …` re-exec exits **0**, masking the
  real error code from callers/scripts.
- **low** `libs/authlib.sh:6` — `root_only` echoes `SC_UID0 true` to stdout on every
  root-only command (leftover debug), polluting captured/parsed output.
- **low** `libs/moduleslib.sh:3-9` — `reset_modules` misses `/root/.srvctl/modules.conf`,
  the cache root actually uses (`commonlib.sh:416-419`), and is never called: dead and
  incomplete.
- **low** `commands/customize.sh:31-34` — copies from `$SC_INSTALL_DIR/commands/$arg.sh`,
  a directory that does not exist in v3 (verified) — dead branch from v2.
- **low** `commands/update-install.sh:50-59` — the interactive `mcedit /etc/hostname`
  branch is unreachable: line 22-28 already exited when `$ARG` is empty.
- smell `commands/update-install.sh:74-79` — ssh-keyscan output appended to
  `~/.ssh/known_hosts` on every run; unbounded duplicate growth.
- smell `libs/fedoralib.sh:33-82` = `libs/systemdlib.sh:3-52` — byte-identical
  `add_service`/`rm_service` maintained twice; alphabetical lib order means systemdlib
  silently wins.
- smell `completion.sh:3,94` — sourcing the completion file (every interactive bash) spawns
  a full background srvctl run and prints the entire hint list to the terminal (plus a
  `sleep 1` when hints are missing); the srvctl path is hardcoded.
- smell `commands/update-install.sh:38` — `/etc/selinux/config` replaced with one line,
  dropping `SELINUXTYPE=` (defaults to targeted, but fragile).

## Polish risks (a rewrite must preserve)
- Exit codes: `customize` exit 23 on missing ARG (`customize.sh:13`); `argument` exit 32
  (`authlib.sh:28`); `root_only`/`reseller_only` exit 44 (`authlib.sh:10,20`);
  `update-install` **exit 5** after setting a first hostname (`update-install.sh:63`) —
  install automation keys off this; exit 0 both for the no-ARG host path
  (`update-install.sh:27`) and after `service_action` via `exit_0` (`command.sh:90`);
  `service_action` returns 66/223 internally (`adjust-servicelib.sh:57,61`).
- Output strings parsed/expected by humans and scripts:
  `"ASSUME system-service: $service"` / `"ASSUME user-service: $service"` (`command.sh:63,80`);
  `"$HOSTNAME update-install complete"` (`update-install.sh:17`);
  `"update-install complete. please reboot."` (`update-install.sh:95`);
  `"-- software-versions --"` (`version.sh:9`); `msg_version_installed` format
  `"$1 ${v:13:8} ${i:13}"` / `"$1 not installed"` (`fedoralib.sh:27,29`);
  `"srvctl version $(cat $SC_INSTALL_DIR/version)"` (`diagnose.sh:23`);
  `"SC_UID0 true"` on stdout from `root_only` (`authlib.sh:6`) — dubious but currently
  emitted inside every root command's output.
- Help/metadata markup: `## @@@` arg specs, `## @en` hints, `## &en` help lines in every
  command file (parsed by commonlib `hint_on_file`/`help_on_file` via `HEMP/HINT/HELP`
  offsets `:7`), and the `## spec //services×…` lines in `command.sh:18-22` consumed by
  gui `make_commands_spec` (`modules/gui/libs/spec.sh:59`). The literal `root_only` /
  `reseller_only` tokens in the first 20 lines of a command file drive help visibility
  (`commonlib.sh:219,223`) — keep the bare `root_only` call near the top of
  update-install.sh.
- Paths/files: `/etc/bash_completion.d/srvctl-completion`;
  `/var/local/srvctl/completion/$USER.{hints,commands,arguments,units,VE}` — file names,
  the word-list format, and 660 perms are load-bearing for `completion.sh` and for the
  login-time `display`; `/etc/srvctl/system/$NAME.service` symlinks (external convention);
  `/etc/srvctl/debug.conf` containing `DEBUG=true`; `$SC_HOME/srvctl-includes/$arg.sh` and
  backup dir `$SC_HOME/.srvctl/srvctl-includes.bak/$arg-$NOW.sh` (`customize.sh:24-25`).
- Semantics: op aliases `? ! + -` map to status/restart/start/stop in srvctl.sh:92-100
  (core, not here) — command.sh only accepts the long ops; `start` and `restart` both mean
  `systemctl enable + restart` and `stop` does NOT disable (only `disable` does)
  (`adjust-servicelib.sh:33-56`); bare `sc SERVICE` = journalctl since yesterday
  (`adjust-servicelib.sh:21-25`); wheel-group users may operate services without sudo
  (`adjust-servicelib.sh:29`); unit-type search order and the two dir lists in
  `command.sh:52,68`; `sc complicate` regenerates completion (init.sh:188-192) and prints
  `"srvctl command-completion has been updated for $SC_USER@$HOSTNAME"`.
- `sudomize` re-exec contract: `sudo $SC_INSTALL_DIR/srvctl.sh $SC_COMMAND_ARGUMENTS`,
  word-split through `run`'s unquoted `$*` (`authlib.sh:50`, `lablib.sh:105`) — sudoers
  entries generated by usersonhost target exactly `$SC_INSTALL_DIR/srvctl.sh *`.
- update-install ordering: dnf update happens even with no ARG; init.sh regeneration of
  `/etc/srvctl` from `/etc/srvctl/data` and module re-test happen BEFORE the command body;
  hooks run as `pre-update-install-host` → `update-install-host` → `post-…`.

## v4 notes
- This module is core in disguise (condition hardwired `true`; authlib/fedoralib/systemdlib
  used by nearly every module). In v4, authlib (permission model), package ops, and
  service_action belong in the core runtime (.mjs), not in a plugin.
- The self-update story should become explicit: v3 has *no* code update step —
  `update-install` = OS update + config regen + hook fan-out, while code arrives via
  `/bin/pop` (dev) or manual clone. v4 needs a first-class `sc update` that pulls/verifies
  the code (version file `3.2.5.9` → semver check), then runs migrations/hooks, replacing
  the fragile symlink/cat completion install (the blocker above must be fixed *before*
  rollout, since v4 will be delivered through this flow).
- Duplication to collapse: add_service/rm_service (fedoralib vs systemdlib); the
  system/user unit-dir scan appears twice in command.sh and again in completionlib
  (`$user.units`) — one unit-enumeration helper; the op-normalization lists appear in
  srvctl.sh, command.sh and completion.sh.
- completion: generate data as JSON from the same registry that serves help/gui spec
  (`## @@@` parsing already exists in three consumers: hint_on_file, completionlib
  complicate, gui spec.sh). The login-time `display` MOTD and per-shell background
  `complicate` run should be opt-in.
- service ops: propagate systemctl exit codes (drop unconditional `exit_0`), drop the
  777 completion dir (per-user files under `~/.srvctl` or 755 root-written dir).
- `run`'s eyif error reporting is broken core-wide (`lablib.sh:106-111` — `eyif` reads the
  `if` condition's `$?`, so it never fires): v4 error handling should not replicate the
  `$?`-capture idiom.
- Vendored `beautify_bash.py` (2011, GPL2) — drop in v4; shfmt or nothing.
