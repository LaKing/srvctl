# module ntp — v3 fact sheet (commit 988c38c)

## Purpose
Ensure the host keeps correct time: during host installation/update it installs the
`ntpsec` package and enables + starts the `ntpd` systemd service. That is the module's
entire functionality — it has no commands, no libs, no conf, and only one hook.
Two files total: `module-condition.sh` (3 lines) and `hooks/update-install-host.sh` (7 lines).

## Activation
`modules/ntp/module-condition.sh` is just `echo true` — the module is **unconditionally
enabled** everywhere (host, container, root, user); `SC_USE_NTP=true` is cached in
`modules.conf` by the module-test loop in `commonlib.sh:427-449`.
History: until 3.2.0.8 (deab3f2, 2019) the condition sourced the `containers`
module-condition (i.e. host-only); it was simplified to `echo true`. Harmless in practice
because the only hook is `update-install-host`, which core only fires on hosts
(`modules/srvctl/commands/update-install.sh:83`, after the container branch exits at line 18).
Note: the file has no trailing newline and uses the `#! /bin/bash` shebang spelling.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | - | - |

(No `commands/` directory — the module exposes no CLI commands and therefore no `## @en` help text.)

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/update-install-host.sh` | `run_hooks update-install-host`, fired by `update-install` on hosts only (update-install.sh:83); sourced by `run_hook` (commonlib.sh:85-108) when `SC_USE_NTP=true` | `sc_install ntpsec` (→ `run dnf -y -q install ntpsec`, fedoralib.sh:6-12), then `run systemctl enable ntpd`, then `run systemctl start ntpd` |

No `pre-`/`post-` variants, no `update-install-ve` hook (containers get no time daemon — correct, since nspawn containers share the host clock).

## Libs
- (no `libs/` directory)

## Config & templates
- (no `conf/` directory)

## State touched
- **Packages**: installs `ntpsec` via dnf on the host.
- **systemd units**: enables and starts `ntpd.service` (unit name shipped by Fedora's ntpsec package).
- **Network**: ntpd binds UDP 123 on the host and talks to upstream NTP pool servers (default distro `/etc/ntp.conf`; the module ships/edits no config).
- No datastore keys, no container paths, no files written by the module itself.

## Dependencies
- Core helpers: `sc_install` (modules/srvctl/libs/fedoralib.sh:6 — **Fedora-only**; fedoralib returns early when `ID != fedora`, so on other distros `sc_install` is undefined → exit 127 inside the hook), `run` (lablib.sh:93).
- Depends on the `srvctl` module's `update-install` command to ever be executed.
- External binaries: `dnf`, `systemctl`.
- Assumes the `ntpsec` Fedora package provides a unit literally named `ntpd.service`.

## Bugs & smells
- **medium** `modules/ntp/hooks/update-install-host.sh:6` — the hook's last command is `run systemctl start ntpd`; its exit code becomes the sourced hook's return status, and `run_hook` follows every hook with `exif` (commonlib.sh:104), which **exits the whole `update-install` run**. If ntpsec failed to install (dnf/network error) or ntpd cannot start, `update-install` aborts here, skipping the `update-install-host` hooks of all alphabetically-later modules (odoo, openvpn, postfix, srvctl, ssh, ve, …, per glob ordering in srvctl.sh:71-75) plus `make_commands_spec`, completion install, and `set_permissions` (update-install.sh:85-94). Worse, the failure is *silent* at the point of origin: `run` suppresses its `eyif` warning whenever `$1 == systemctl` (lablib.sh:108-111), so the only message is the generic "…/modules/ntp hook 'update-install-host' failed".
- **low** `modules/ntp/hooks/update-install-host.sh:5-6` — chronyd (Fedora's default time daemon) is never disabled. `systemctl start ntpd` stops a running chronyd via unit `Conflicts=`, but chronyd stays *enabled*, so after reboot two enabled, mutually conflicting time daemons race; which one wins is transaction-order dependent, and the host can end up back on chronyd or with neither running.
- **low** `modules/ntp/hooks/update-install-host.sh:3` — no idempotence guard (compare `named/libs/install.sh:10-11` or `update-install.sh:42-44` which test for the binary first); every `update-install` re-runs `dnf install`, costing time and failing the whole run (see medium bug) when the machine is offline even though ntpd is already installed and running.
- Cross-module (belongs to `named`'s sheet but discovered here): `modules/named/libs/install.sh:11,13-14` duplicates this hook but still installs the retired `ntp` package — the ntp module itself was fixed to `ntpsec` only in e179f53 (2026-07-04); the two code paths now install *different* packages for the same `ntpd.service`.

## Polish risks
- Hook filename `hooks/update-install-host.sh` and the module directory name `ntp` — `run_hook` derives `SC_USE_NTP` from the directory name (commonlib.sh:90-91) and matches hook files by exact name (commonlib.sh:100).
- `module-condition.sh` must **echo** exactly the string `true` to stdout (commonlib.sh:436-441); anything else disables the module. The cached line written is `export SC_USE_NTP=true` in `/var/local/srvctl/modules.conf` (commonlib.sh:447).
- Package name `ntpsec` (update-install-host.sh:3) and unit name `ntpd` (lines 5-6) — a rewrite must keep the enable+start pair and the `run` wrapper's console echo format `[user@host dir]# systemctl enable ntpd` (lablib.sh:93-115).
- Failure propagation contract: hook's return status flows into `exif` (commonlib.sh:104) → process exit with the command's code and stderr line `[ host ] /path/modules/ntp hook 'update-install-host' failed`. Whether v4 wants to keep abort-on-failure is a design decision, but changing it changes update-install semantics for *all* modules.

## v4 notes
- This is the smallest possible module: one package + one unit at host-install time. In v4 this collapses to a declarative entry (e.g. `{ packages: ["ntpsec"], units: ["ntpd"] }`) consumed by a generic "ensure installed + enabled" provisioner in .mjs — the same pattern appears verbatim in ftp (`sc_install vsftpd`), codepad, firewalld, named, perdition, letsencrypt, mariadb, gluster hooks/libs; one shared `ensurePackageService(pkg, unit)` kills ~10 copies.
- Use `systemctl enable --now` semantics and check `systemctl is-active` first for idempotence; explicitly `disable --now chronyd` (or adopt chronyd instead of ntpsec — worth a design decision, since chrony is the Fedora default and would make this module deletable).
- Reconcile with `named/libs/install.sh` which still installs retired `ntp`; only one component should own time sync.
- Consider whether the module should be condition-gated to hosts (`containers` condition, as pre-2019) instead of `echo true`, so `SC_USE_NTP` isn't misleadingly true inside containers.
