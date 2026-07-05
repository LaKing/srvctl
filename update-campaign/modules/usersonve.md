# Module usersonve — v3 fact sheet (commit 988c38c)

## Purpose
Container-side (VE-only) user and appliance provisioning. Provides `add-user` (create/update a Linux user inside a container with a generated password, `.password` file and welcome mail) plus three kiosk/appliance installers built around a dedicated user `x`: `vnc-desktop` (TigerVNC remote desktop on display :0, no auth), `install-crossover` (CrossOver/Wine kiosk) and `install-qlcplus` (QLC+ DMX light controller kiosk). Also joins containers to ZeroTier networks (`add-zerotier`, currently USER WIP). One hook runs `dnf -y update` during `update-install`.

## Activation
`modules/usersonve/module-condition.sh:3` simply sources `modules/ve/module-condition.sh`, which echoes `true` iff `systemd-detect-virt -c` reports `systemd-nspawn` or `lxc` (`modules/ve/module-condition.sh:3-10`). So the module (all commands + the hook) is enabled **only inside containers**, never on the host. Result is cached as `SC_USE_USERSONVE=true` in the modules.conf cache (`commonlib.sh:430-448`).

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| `add-user USERNAME` | "Add user to the container" | Lowercases `$ARG`, validates against regex (unanchored — see Bugs), `adduser` if missing (else `err` but continues, i.e. add-or-update). Password: reuse `$home/.password` if present, else `new_password` (node helper from the password module). Sets it via `passwd --stdin` (output discarded), rewrites `.password`, prints it via `ntc`. | Creates system user; writes plaintext `$home/.password`; sends welcome mail to `$username@$HOSTNAME` via `mail`; `chown -R $username:$username $home`. No `$SRVCTL` guard, no `root_only`/`ve_only` (relies on module condition + being root). Exit 22 on invalid name, 32 via `argument` if missing. |
| `add-zerotier NETWORKID` — **USER WIP** (uncommitted changes; excluded from rewrite) | "Install ZeroTier and add a network" | Guard `[[ $SRVCTL ]] \|\| exit 4`; `ve_only; root_only`. If no ARG, looks up network ID by hostname prefix (`zt-$prefix`) in `/var/srvctl3/share/common/zerotier-one/devicemap` (awk on `key=value`), exits 1 if not found, bare `exit` (0!) if no devicemap. Imports ZeroTier GPG key, pipes verified `install.zerotier.com` script to bash, symlinks global devicemap, `dnf update zerotier-one`. When no ARG: resets ZeroTier identity (stop service, delete `identity.*`, `peers.d`, restart). Joins network; if devicemap maps the ID to an interface, restarts firewalld and adds the interface to the trusted zone permanently. WIP diff vs HEAD: added `sleep 1`/`sleep 2`, `run systemctl restart firewalld`, wrapped firewall-cmds in `run`, extra `zerotier-cli info`, message tweaks. | Installs zerotier-one from upstream script; deletes/recreates node identity; `/var/lib/zerotier-one/devicemap` symlink; permanent firewalld trusted-zone change + reload. |
| `install-crossover` | "Crossover/wine for user x with VNC and ratpoison" | Guard `exit 4`; `ve_only; root_only`. `sc_install` crossover.rpm from codeweavers URL + gtk3/perl/vte + long i686 and x86_64 dependency lists. Symlinks `/bin/crossover` and shared license files if present. Writes `/home/x/.ratpoisonrc` (exec crossover) and `/home/x/autostart.sh` (xbindkeys + exec crossover), `chown x:x`, `chmod +x`. | Package installs incl. 32-bit libs; `/bin/crossover`, `/opt/cxoffice/etc/license.{sig,txt}` symlinks; overwrites `/home/x/.ratpoisonrc` and `/home/x/autostart.sh`. Assumes user `x`/`/home/x` exist (from `vnc-desktop`). |
| `install-qlcplus` | "QLC+ light controller for dmx on artnet" | Guard `exit 4`; `ve_only; root_only`. Writes `/etc/yum.repos.d/mcallegari79.repo` (hardcoded Fedora_38 OBS repo), `dnf install qlcplus-qt5` + `exif`, installs xbindkeys, unconditionally rewrites `/home/x/autostart.sh` (always-true `[[ /home/x/autostart.sh ]]`, see Bugs) to exec `qlcplus --nowm -o /home/x/default.qxw -p`. "Syncs" fixtures from share (broken by path typo, see Bugs). Reports whether `default.qxw` exists but never creates it. | New yum repo; packages; clobbers `/home/x/autostart.sh`; creates root-owned `/home/x/.qlcplus/fixtures` with empty files. |
| `vnc-desktop [DESKTOP]` | "Add user x with a virtual desktop:0 with gnome, ratpoison, ..." | Guard `exit 4`; `ve_only; root_only`. `DESKTOP` defaults to `none`. Installs tigervnc-server (`exif` on failure), `adduser x`, writes `/usr/share/xsessions/none.desktop` (Exec=/home/x/autostart.sh). `gnome` arg: prints "unimplemented" and exits 0. Other args: lists desktop groups, `dnf -y install "$DESKTOP"` if not `none`. Opens firewalld `vnc-server` service permanently. Writes `/home/x/.vnc/config` (session=$DESKTOP, **securitytypes=none**, 1920x1080), `/etc/tigervnc/vncserver.users` (`:0=x`), `.xbindkeysrc` binding Ctrl+Alt+Del to autostart.sh, seed `/home/x/autostart.sh` (xbindkeys only), and `/etc/systemd/system/vncserver.service` (forking, `/usr/libexec/vncsession-start :0`, SELinuxContext vnc_session_t, Restart=always). daemon-reload, enable, restart, status; lists xsessions. | User `x`; unauthenticated VNC service on :0 enabled at boot; permanent firewall opening; overwrites tigervnc user mapping and several files under `/home/x`. |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/update-install-host.sh` | `run_hooks update-install-host` from `modules/srvctl/commands/update-install.sh:83` (only `$hook` phase exists; run via `run_hook` for enabled modules, `commonlib.sh:85-114`) | `run dnf -y update` — a full package update of the container. Despite the `-host` suffix it only ever runs **inside VEs** (module is VE-only), i.e. every `sc update-install` executed in a container triggers a full dnf update. Header comment ("list commands to install certain tools") does not match behavior. |

## Libs
- (no `libs/` directory). Consumes libs from other modules: `ve_only` (containers/libs/authlib.sh:13), `root_only`/`argument` (srvctl/libs/authlib.sh:3,24), `new_password` (password/libs/bashlib.sh:3, node-backed), `sc_install` (srvctl/libs/fedoralib.sh:6, Fedora-gated `dnf -y -q install`).

## Config & templates
- (no `conf/` directory). All config is generated inline via heredocs: `mcallegari79.repo`, `none.desktop`, `.vnc/config`, `vncserver.users`, `vncserver.service`, `autostart.sh`, `.ratpoisonrc`, `.xbindkeysrc`.

## State touched
- Container users/groups: arbitrary user via `add-user`; fixed user `x` for kiosk commands.
- Files: `$home/.password` (plaintext password), `/home/x/{autostart.sh,.ratpoisonrc,.xbindkeysrc,.vnc/config,.qlcplus/fixtures/*}`, `/usr/share/xsessions/none.desktop`, `/etc/tigervnc/vncserver.users`, `/etc/systemd/system/vncserver.service`, `/etc/yum.repos.d/mcallegari79.repo`, `/bin/crossover`, `/opt/cxoffice/etc/license.{sig,txt}`, `/var/lib/zerotier-one/{devicemap,identity.*,peers.d}`.
- systemd units: `vncserver.service` (created+enabled), `zerotier-one` (stop/start), `firewalld` (restart, WIP).
- Firewalld: `vnc-server` service opened permanently; ZeroTier interface added to `trusted` zone permanently.
- Shared host assets (read, bind-mounted share): `/var/srvctl3/share/common/{crossover/license.*,qlcplus/fixtures,zerotier-one/devicemap}`.
- Network: downloads from codeweavers.com, opensuse.org, install.zerotier.com, raw.githubusercontent.com; joins ZeroTier network; sends local mail.
- Datastore keys: none.

## Dependencies
- Core helpers: `msg ntc err run exif eyif` (lablib.sh), `argument` (exit 32), `root_only`/`ve_only` (exit 44), `new_password` (needs node + password module), `sc_install` (Fedora only — kiosk installers silently lose `sc_install` on non-Fedora since fedoralib returns early on `$ID != fedora`).
- Modules assumed: `ve` (condition file sourced directly by path), `password`, `srvctl`, `containers` (authlib), working `share/common` mount from the host.
- External binaries: `adduser`, `passwd` (`--stdin`, shadow-utils), `mail` (mailx), `getent`, `dnf`, `firewall-cmd`, `systemctl`, `curl`, `gpg`, `awk`, `zerotier-cli` (post-install), `tigervnc` (`vncsession-start`), `xbindkeys`.
- Env: `SRVCTL`, `ARG`, `SC_ON_VE`, `SC_UID0`, `SC_INSTALL_DIR`, `HOSTNAME`.

## Bugs & smells
- **medium** `commands/install-qlcplus.sh:60` — source path typo `qlcpuls` (listing on :57 uses correct `qlcplus`): every `cat` fails but the `>` redirection still truncates/creates the target, so fixture sync is completely broken and leaves **empty** fixture files in `/home/x/.qlcplus/fixtures/` (also mislabeled in the msg on :56).
- **medium** `commands/install-qlcplus.sh:38` — `if [[ /home/x/autostart.sh ]]` is a non-empty-string test (missing `-f`), always true; `/home/x/autostart.sh` is unconditionally overwritten, clobbering e.g. the CrossOver autostart written by install-crossover.
- **medium** `commands/install-qlcplus.sh:54` — `mkdir -p /home/x/.qlcplus/fixtures` as root with no chown: QLC+ runs as user `x` but its config dir and fixture files are root-owned, so it cannot save configuration/workspaces.
- **medium** `commands/add-user.sh:13` — validation regex `([a-z_][a-z0-9_]{0,30})` is unanchored: any input containing one valid run passes (e.g. `bad!name`, `-flag`), defeating validation; `adduser` then fails or misparses.
- **medium** `commands/add-user.sh:27,40,41` — if the user doesn't exist after `adduser` (failed add), `home` is empty: the password is written to `/.password` at filesystem root (:41), `passwd` failure is invisible because stdout+stderr are discarded (:40), and :38 still prints a password that was never set — misleading success.
- **low** `commands/add-user.sh:41` — plaintext password persisted in `$home/.password`, created with root's umask (typically 0644) before the recursive chown; `echo -e` additionally mangles passwords containing backslash sequences. Re-running add-user on an existing user silently resets their password to the stale `.password` content (:29-36).
- **low** `commands/add-user.sh:1-8` — missing `[[ $SRVCTL ]]` guard (every sibling command has one); executed directly with bash it stumbles through undefined helpers (`argument`, `err`) because there is no `set -e`.
- **USER WIP, medium** `commands/add-zerotier.sh:41` — line ends with `&& \␣␣` (backslash escapes a *space*, not the newline): the command after `&&` is a literal-space word → "command not found" (127) and the GPG-import chain never gates line 42; the installer pipeline runs regardless. Present in HEAD too.
- **USER WIP, low** `commands/add-zerotier.sh:34` — bare `exit` after `err "No network specified"` exits 0: error path reports success to callers/hooks. Present in HEAD too.
- **low** `commands/vnc-desktop.sh:112-114` — `xbindkeys --defaults > /home/x/.xbindkeysrc` is immediately truncated by `echo '' > /home/x/.xbindkeysrc`; dead work, defaults intentionally(?) discarded.
- **low** `commands/vnc-desktop.sh:58` — the `gnome` branch prints "unimplemented" then bare `exit` (status 0): requesting gnome silently succeeds while doing nothing.
- **low** `commands/vnc-desktop.sh:63` — unquoted `dnf group list --available *desktop`: the glob expands against files in the caller's cwd if any match.
- **low** `commands/install-crossover.sh:29,35-36` — `ln -s` without `-f`: re-runs emit failure warnings (idempotency broken, cosmetic).
- **smell** `commands/vnc-desktop.sh:93` + `:79` — `securitytypes=none` plus permanently opened `vnc-server` firewall service = unauthenticated remote desktop; intentional kiosk design but security-sensitive, must be a conscious decision in v4.
- **smell** `hooks/update-install-host.sh:5` — hook named `-host` but only ever runs inside VEs; a full `dnf -y update` as a side effect of `sc update-install` is slow and surprising; header comment doesn't match behavior.
- **smell** `commands/install-qlcplus.sh:26` — OBS repo hardcoded to `Fedora_38`; stale on newer container releases (`$VERSION_ID` unused).
- **smell** `commands/install-qlcplus.sh:57` — `for f in $(ls ...)` breaks on filenames with spaces; errors if share dir missing.

## Polish risks
- Help metadata parsed by `sc help`: exact `## @@@` / `## @en` / `## &en` lines in all five commands (add-user.sh:3-6, add-zerotier.sh:3-5, install-crossover.sh:3-5, install-qlcplus.sh:3-5, vnc-desktop.sh:3-7) — command names and hints must stay byte-identical.
- Exit codes: `exit 4` on missing `$SRVCTL` (add-zerotier.sh:8, install-crossover.sh:8, install-qlcplus.sh:8, vnc-desktop.sh:11 — note: 4, not the conventional 10); `exit 22` invalid username (add-user.sh:16); `exit 32` from `argument` (srvctl authlib); `exit 44` from `ve_only`/`root_only`; add-zerotier `exit 1` when devicemap lookup fails (add-zerotier.sh:28).
- Operator-visible strings: `Password for $username is: $password` (add-user.sh:38); mail subject `Welcome to $HOSTNAME` and body text (add-user.sh:43); `User $username already exist.` (add-user.sh:21).
- Contract: `add-user` is add-or-update; `$home/.password` is both output and input — an existing `.password` is reused verbatim on re-run (add-user.sh:29-36,41).
- Generated file paths/contents other tooling depends on: `/home/x/autostart.sh` as the single kiosk entry point referenced by `none.desktop` Exec (vnc-desktop.sh:48) and `.xbindkeysrc` Ctrl+Alt+Del binding (vnc-desktop.sh:115-116); `/usr/share/xsessions/none.desktop` (vnc-desktop.sh:44-51); `/home/x/.vnc/config` keys `desktop="D250 Laboratories"`, `session=$DESKTOP`, `securitytypes=none`, `geometry=1920x1080` (vnc-desktop.sh:87-96); `/etc/tigervnc/vncserver.users` mapping `:0=x` (vnc-desktop.sh:107); unit name `vncserver` with `ExecStart=/usr/libexec/vncsession-start :0`, `PIDFile=/run/vncsession-:0.pid`, `SELinuxContext=system_u:system_r:vnc_session_t:s0`, `Restart=always` (vnc-desktop.sh:137-154); repo id `home_mcallegari79` file `/etc/yum.repos.d/mcallegari79.repo` (install-qlcplus.sh:22-31); symlinks `/bin/crossover` (install-crossover.sh:29) and license symlinks (install-crossover.sh:35-36); devicemap symlink target `/var/lib/zerotier-one/devicemap` (add-zerotier.sh:47).
- Shared-asset paths on the host side: `/var/srvctl3/share/common/{crossover,qlcplus,zerotier-one}` (install-crossover.sh:32, install-qlcplus.sh:57, add-zerotier.sh:21).
- Firewalld state: permanent `vnc-server` service (vnc-desktop.sh:79) and permanent trusted-zone interface for ZeroTier (add-zerotier.sh:78) — persistence across reboots is relied on.
- Module visibility: commands must only exist inside containers (module-condition via `ve`), keeping host `sc` namespace clean.
- add-zerotier.sh is USER WIP — exclude from any rewrite; preserve as-is.

## v4 notes
- The three installers share a "kiosk user x" pattern (create user x, autostart.sh contract, xbindkeys, chown) — extract a single kiosk/appliance helper or make autostart.sh composition explicit instead of three heredocs that clobber each other.
- `add-user` is the only genuine "users on VE" command; the kiosk/appliance installers (vnc/crossover/qlcplus) and zerotier arguably belong in a separate `appliance`/`kiosk` module in v4 — they are device-provisioning, not user management.
- Password handling: replace plaintext `.password` with the password module/datastore, set proper file mode (0600) at creation, use `chpasswd` instead of `passwd --stdin` with discarded output; anchor the username regex (`^...$`).
- Derive the QLC+ OBS repo release from `$VERSION_ID` instead of hardcoded Fedora_38; fix `qlcpuls` typo and ownership; use `install -o x -g x` style file drops.
- Hook: rename/replan `update-install-host` (it is VE-side); decide whether a full `dnf update` belongs in srvctl's own update path at all, or behind an explicit flag.
- In .mjs terms: file generation (units, desktop files, repo files) is a natural fit for template functions with declared ownership/mode; package installation and firewalld changes should go through shared helpers with idempotency checks (ln -sf, `firewall-cmd --query-*` before add).
- add-zerotier: USER WIP, out of scope for the rewrite; its devicemap/hostprefix lookup logic (awk over `key=value`) is a candidate for a shared devicemap helper later.
