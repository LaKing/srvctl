# saslauthd — v3 fact sheet (commit 988c38c)

## Purpose
Provides SMTP AUTH for the host's postfix by installing/configuring the cyrus-sasl `saslauthd` daemon in `rimap` mode against `localhost` (the perdition IMAP proxy, which routes to the per-domain mail containers). Effectively: mail users authenticate to host postfix with `user@domain`, saslauthd verifies via IMAP login through perdition. Ships two operator commands: a saslauthd restart ("fix mailing") and an end-to-end auth test for a container user.

## Activation
`module-condition.sh:3` simply sources the containers module condition (`$SC_INSTALL_DIR/modules/containers/module-condition.sh`). So `SC_USE_SASLAUTHD` is true exactly when the containers module is true: not `localhost.localdomain`, not running inside a container (`systemd-detect-virt -c` not nspawn/lxc), `$SC_HOSTNET` set or `/etc/srvctl/data` exists, and `$HOSTNAME` present in `/etc/srvctl/hosts.json`; or `CMD == update-install` with an `$ARG`. Conditions are evaluated in a subshell (`commonlib.sh:436`), so the `readonly SC_VIRT` inside the sourced file is harmless.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| `fix-saslauthd` (`commands/fix-saslauthd.sh`) | "restart saslauthd" | Guard `[[ $SRVCTL ]] || exit 4`; `sudomize` (non-root re-execs via sudo); `systemctl restart saslauthd`; on success prints unit status + `msg "Successfully restarted saslauthd"`, else `err "Saslauthd Restart FAILED"` | Restarts host `saslauthd.service`; drops in-flight SASL auth requests |
| `testsaslauthd user@ve` (`commands/testsaslauthd.sh`) | "test a given user of a container for email-functionality" | Guard exit 4; `root_only`; `hs_only`; `sudomize` (dead after root_only, see Bugs); splits `$ARG` at `@` into user/domain; reads plaintext password from `/srv/$domain/rootfs/home/$user/.password`, then (overriding) `/srv/mail.$domain/rootfs/home/$user/.password`; if none found echoes `Mission failed.` but continues; runs `run testsaslauthd -u "$ARG" -p "$password"` | Reads container-home password files; echoes plaintext password to terminal via `run`; performs a real auth against saslauthd→perdition→mail container |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/regenerate.sh` | `run_hook regenerate` (fired by `add-ve`, `add-ve-user`, `add-network-ve`, `add-codepad`, `regenerate` command, regenlib — 11 call sites) | Calls lib `restart_saslauthd` — restarts saslauthd.service, verifies `systemctl is-active`, msg/err accordingly |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` from `modules/srvctl/commands/update-install.sh:83` (host install/update) | `dnf -y install cyrus-sasl`; writes `/etc/sasl2/smtpd.conf` (`pwcheck_method: saslauthd`, `mech_list: LOGIN`); `run saslauthd -v`; copies module conf to `/etc/sysconfig/saslauthd`; copies module unit to `/usr/lib/systemd/system/saslauthd.service`; `add_service saslauthd` (symlink into `/etc/srvctl/system/`, enable, restart, status); `systemctl daemon-reload` (after the restart — see Bugs). A commented-out block (lines 14-17) used to install the vendored patched saslauthd binary |
| `hooks/version.sh` | none — no `run_hook version`/`run_hooks version` call site exists anywhere in the tree | Would run bare `saslauthd -v`; dead code at this commit |

## Libs
| function | provided by | used by |
|---|---|---|
| `restart_saslauthd` | `libs/systemdlib.sh:3` — restart unit, check `is-active`, `msg "restarted saslauthd.service"` or `err "saslauthd restart FAILED!"` + status | Only `hooks/regenerate.sh:3` in this module; no other module/core reference found. Loaded globally via `load_libs` whenever the module is enabled (function name collides with nothing; note core has *two* `add_service` definitions elsewhere, not in this module) |

## Config & templates
- `conf/saslauthd.conf` — sysconfig template: `SOCKETDIR=/run/saslauthd`, `MECH=rimap`, `FLAGS="-n 0 -O localhost -r"`. Installed verbatim to `/etc/sysconfig/saslauthd` by `hooks/update-install-host.sh:23`.
- `services/saslauthd.service` — unit: `Type=forking`, `PIDFile=/run/saslauthd/saslauthd.pid`, `EnvironmentFile=/etc/sysconfig/saslauthd`, `ExecStart=/usr/sbin/saslauthd -m $SOCKETDIR -a $MECH $FLAGS`, `RuntimeDirectory=saslauthd`. Installed to `/usr/lib/systemd/system/saslauthd.service` by `hooks/update-install-host.sh:25`.
- `/etc/sasl2/smtpd.conf` generated inline by the hook (not a template file): `pwcheck_method: saslauthd`, `mech_list: LOGIN` — consumed by host postfix (`modules/postfix/conf/hs-main.cf:67` `smtpd_sasl_type = cyrus`).
- `bin/saslauthd` (2016) and `bin/1.2.27.rc6/{saslauthd,testsaslauthd}` (2018) — vendored x86_64 ELF binaries, ~475 KB total, no longer installed by any code path (the `cp` at `hooks/update-install-host.sh:16` is commented out).

## State touched
- Host files: `/etc/sasl2/smtpd.conf` (overwritten), `/etc/sysconfig/saslauthd` (overwritten), `/usr/lib/systemd/system/saslauthd.service` (overwritten, RPM-owned path), `/etc/srvctl/system/saslauthd.service` (symlink via `add_service`).
- Runtime: `/run/saslauthd/` (socket `mux`, pid file) via `RuntimeDirectory`.
- systemd: `saslauthd.service` enable/restart/status/daemon-reload.
- Packages: installs `cyrus-sasl` via dnf.
- Container paths (read-only): `/srv/<domain>/rootfs/home/<user>/.password`, `/srv/mail.<domain>/rootfs/home/<user>/.password`.
- Network: saslauthd dials IMAP on `localhost` (perdition) for rimap verification; module opens no ports itself.

## Dependencies
- Core/lib helpers: `msg`, `err` (lablib.sh:23,87), `run` (lablib.sh:93 — echoes the full command line then executes it, `eyif`-warns on nonzero), `exif` (wraps every hook/command source in commonlib.sh:104,163), `sudomize`/`root_only` (modules/srvctl/libs/authlib.sh:46,3), `hs_only` (modules/containers/libs/authlib.sh:3), `add_service` (defined twice: modules/srvctl/libs/systemdlib.sh:3 and modules/srvctl/libs/fedoralib.sh:33).
- Modules assumed: `containers` (condition is literally its condition), `perdition` (rimap target on localhost), `postfix` (consumer of `/etc/sasl2/smtpd.conf`), `usersonve`/`usersonhost` (create the `.password` files that `testsaslauthd` reads).
- External binaries: `dnf`, `systemctl`, `saslauthd`, `testsaslauthd` (both from cyrus-sasl RPM), `cut`, `cat`.

## Bugs & smells
- **medium** `commands/testsaslauthd.sh:31-36` — when no `.password` file is found it only `echo`s "Mission failed." (to stdout, not `err`) and does **not** exit; it still executes `run testsaslauthd -u "$ARG" -p ""`, attempting a real authentication with an empty password (and with an empty `-u` when `$ARG` is missing, since there is no `argument` guard). Harm: misleading failure path, pointless auth attempt, exit status comes from testsaslauthd rather than a clean error.
- **medium** `commands/testsaslauthd.sh:36` — the plaintext mailbox password is passed as a CLI argument through `run`, which prints the full command line to the terminal (lablib.sh:126) and exposes it in the process list for the duration of `testsaslauthd`. Harm: credential leakage to screen/scrollback/`ps`.
- **medium** `hooks/update-install-host.sh:25` — the customized unit is written to the RPM-owned path `/usr/lib/systemd/system/saslauthd.service` instead of `/etc/systemd/system/`. Harm: any `dnf update cyrus-sasl` silently replaces it with the stock unit, reverting the deployment until the next `update-install`; `rpm -V` flags the host.
- **medium** `hooks/update-install-host.sh:27-29` — `systemctl daemon-reload` runs **after** `add_service saslauthd` has already enabled and restarted the service, so the first restart after a unit-file change can run the stale in-memory unit definition (systemd "unit file changed on disk" warning). Harm: freshly changed ExecStart/RuntimeDirectory not in effect until a later restart.
- **low** `commands/testsaslauthd.sh:11-14` — `root_only` (exits 44 for any non-root caller, modules/srvctl/libs/authlib.sh:3) precedes `sudomize`, making the sudo self-elevation dead code; non-root admins get "Authorization failure" here while the sibling `fix-saslauthd` elevates fine. Harm: inconsistent UX/dead code.
- **low** `commands/testsaslauthd.sh:16-31` — `password` is never initialized, so an exported `password` env var from the caller's shell silently survives the "no file found" check and gets used; `$domain`/`$user` are unquoted inside `[ -f /srv/$domain/... ]`, so an ARG containing spaces/globs makes the test expression error. Harm: wrong credential used / script error on hostile args.
- **low** `hooks/version.sh:3` — dead hook: nothing in the tree invokes a `version` hook (`run_hook version` has zero call sites), so this file never runs. Harm: none at runtime; misleads maintainers.
- **low** `hooks/regenerate.sh:3` — unconditionally restarts saslauthd on *every* `regenerate` (fired by every add-ve/add-user/add-codepad, 11 call sites) even though nothing in saslauthd's config is domain-dependent. Harm: momentary SMTP AUTH outage for all mail users on each container operation.
- **smell** `bin/saslauthd`, `bin/1.2.27.rc6/*` — ~475 KB of orphaned vendored ELF binaries whose only consumer (`hooks/update-install-host.sh:16`) is commented out; dir name "1.2.27.rc6" is likely a typo of cyrus-sasl 2.1.27-rc6.
- **smell** `hooks/update-install-host.sh:21` — `#TODO check this, if it was successful?` — no verification that the install/config actually produced a working saslauthd; `run saslauthd -v` failure only warns via `eyif`.

## Polish risks
- Guard exit code: both commands use `[[ $SRVCTL ]] || exit 4` (fix-saslauthd.sh:9, testsaslauthd.sh:9) — exit 4, not the CLAUDE.md-documented 10; keep as-is per-module.
- Auth exit code 44 from `root_only`/`hs_only` (modules/srvctl/libs/authlib.sh:11, modules/containers/libs/authlib.sh:9).
- `/etc/sasl2/smtpd.conf` exact content: `pwcheck_method: saslauthd` and `mech_list: LOGIN` (update-install-host.sh:9-10) — postfix `smtpd_sasl_type = cyrus` (postfix/conf/hs-main.cf:67) and deployed mail clients depend on the LOGIN mech.
- `/etc/sysconfig/saslauthd` exact values: `SOCKETDIR=/run/saslauthd`, `MECH=rimap`, `FLAGS="-n 0 -O localhost -r"` (conf/saslauthd.conf:3,8,13). The `-r` (append realm to username) is load-bearing: full `user@domain` must reach perdition.
- Unit file semantics: `Type=forking`, `PIDFile=/run/saslauthd/saslauthd.pid`, `EnvironmentFile=/etc/sysconfig/saslauthd`, `ExecStart=/usr/sbin/saslauthd -m $SOCKETDIR -a $MECH $FLAGS`, `RuntimeDirectory=saslauthd` (services/saslauthd.service:5-9).
- Command names/help text: `fix-saslauthd` "restart saslauthd" (fix-saslauthd.sh:3-6), `testsaslauthd user@ve` (testsaslauthd.sh:3-5).
- User-visible strings: `Successfully restarted saslauthd` (fix-saslauthd.sh:18), `Saslauthd Restart FAILED` (fix-saslauthd.sh:20), `restarted saslauthd.service` / `saslauthd restart FAILED!` (libs/systemdlib.sh:11,13), `Container $domain` / `Container mail.$domain` (testsaslauthd.sh:21,27), `Mission failed.` (testsaslauthd.sh:33), `Installing saslauthd - binary for x86_64` (update-install-host.sh:6).
- Password lookup precedence: `/srv/$domain` first, `/srv/mail.$domain` overrides when both exist (testsaslauthd.sh:19-29).
- Lib function name `restart_saslauthd` (libs/systemdlib.sh:3) is globally sourced when the module is on; regenerate hook calls it by name (hooks/regenerate.sh:3).
- `add_service` side effects retained: symlink `/etc/srvctl/system/saslauthd.service`, enable + restart + status (modules/srvctl/libs/systemdlib.sh:3-16).

## v4 notes
- Ideas only: the whole module is "install one daemon + restart it on demand"; in .mjs this collapses to a declarative service spec (package `cyrus-sasl`, three rendered files, unit enable) plus one `restartService('saslauthd')` action reused by both `fix-saslauthd` and the regenerate pipeline — `libs/systemdlib.sh`, `hooks/regenerate.sh`, and `fix-saslauthd.sh` are three copies of the same restart-and-report logic (also near-duplicates of core `add_service`'s restart block).
- Drop the orphaned `bin/` binaries and the dead `hooks/version.sh`; if a version hook is desired in v4, make the dispatcher actually run per-module version hooks.
- Move the unit to `/etc/systemd/system/` (or a drop-in) and do `daemon-reload` before enable/restart.
- `testsaslauthd` should validate its argument, exit on missing password, and pass the secret via stdin/env rather than argv; consider folding it into a generic `mail-diagnose`.
- Enablement is literally the containers condition — in v4 express it as `dependsOn: containers` (plus perdition/postfix, which it silently assumes) instead of re-sourcing another module's condition file.
