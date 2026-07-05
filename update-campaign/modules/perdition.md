# perdition — v3 fact sheet (commit 988c38c)

## Purpose
Runs the Perdition mail reverse-proxy (IMAP4/IMAP4S/POP3S) on containerfarm hosts so that mail clients connecting to the host are routed to the correct per-domain `mail.<domain>` container's dovecot. The module installs the perdition package plus three custom systemd units, and regenerates the user→server routing map (`popmap.re`) from the datastore's `containers.json` on every container regenerate.

## Activation
`module-condition.sh:3` sources `modules/containers/module-condition.sh` verbatim — perdition is enabled exactly when the containers module is: on a real (non-nspawn/non-lxc) host whose `$HOSTNAME` appears in `/etc/srvctl/hosts.json` (with `$SC_HOSTNET` set or `/etc/srvctl/data` present), or during `update-install` with an argument. Never active inside containers.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | This module exposes no `commands/` directory; it is hook/lib only. | - |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/regenerate.sh` | `run_hook regenerate` (from `add-ve`, `add-ve-user`, `add-network-ve`, `add-codepad`, `regenerate` command, `regenlib.sh`) | Calls `perditioncfg` (regenerates `/var/perdition/popmap.re` via node) then `restart_perdition` (restarts the 3 services); ends with `return 0` so failed service restarts do not abort the hook chain (regenerate.sh:7). |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` (from `update-install` command) | Contains only the commented-out line `#install_perdition` (update-install-host.sh:3) — currently a no-op. Prior to commit e179f53 this hook performed the full install inline. |
| `hooks/firewalld.sh` | `run_hooks firewalld` (from firewalld module's `update-install-host.sh`/`update-install-ve.sh` hooks) | `firewalld_add_service imaps` and `pop3s` on the host firewall; additionally `imap` if `${container:0:5} == "mail."` (see Bugs — that branch is dead in the only context that runs this hook). |
| `hooks/mkrootfs_fedora.sh` | `run_hooks mkrootfs_fedora` (from containers module `mkrootfs_fedora.sh:87`, rootfs build) | If `$rootfs_name == mail`, runs `firewalld_offline_add_service imap`, `imaps`, `pop3s` inside the container rootfs being built (chroot firewall-offline-cmd). |
| `hooks/version.sh` | intended for a `version` hook — **no `run_hook version` exists anywhere in the tree**; dead | Would call `msg_version_installed Pound` — wrong package name (should be `perdition`). |

## Libs
(sourced by `load_libs` whenever the module is active; none are referenced from outside this module)
- `libs/bashlib.sh` — `perditioncfg()`: runs `/bin/node $SC_INSTALL_DIR/modules/perdition/perdition.js $* 2>&1` into `__result`, `exif "PERDITION-ERROR cfg $* ($?) $__result"` on failure, echoes captured output on success (bashlib.sh:8-11).
- `libs/install_perdition.sh` — `install_perdition()`: `sc_install perdition`, `install_service_hostcertificate /etc/perdition` (certificates module), writes `/etc/perdition/perdition.conf` from `conf/perdition.conf`, seeds `/etc/perdition/popmap.re`, `mkdir -p /var/run/perdition /var/perdition`, runs `perditioncfg`, deletes the RPM's unit files from `/usr/lib/systemd/system/`, installs the three custom units to `/etc/systemd/system/`, `daemon-reload`, `add_service imap4|imap4s|pop3s`. **Currently has no caller** (only the commented line in update-install-host.sh:3).
- `libs/systemdlib.sh` — `restart_perdition()`: `systemctl restart` + `is-active` check for `imap4s`, `imap4`, `pop3s`; `msg "restarted X.service"` on success, `err "X restart FAILED!"` + `systemctl status --no-pager` on failure. Non-fatal.
- `perdition.js` (invoked by `perditioncfg`, not a lib file): requires `../../lablib.js` and `../datastore/lib.js`; `write_popmap_cfg()` iterates `datastore.containers` keys and writes one line `(.*)@<dom>: <mx>\n` per container (dom = name with leading `mail.` stripped; mx = `mail.<name>` or the name itself if it already starts with `mail.`) to `/var/perdition/popmap.re`. Exit codes: 0 on success (default 99 until callback runs), 111 with `DATA-ERR R:` on write failure (perdition.js:44-48); datastore lib exits 112 with `LIB-ERROR:` if the JSON files are unreadable.

## Config & templates
- `conf/perdition.conf` → copied to `/etc/perdition/perdition.conf` by `install_perdition` (install_perdition.sh:15). Notable directives: `connection_logging`, `log_facility mail`, `bind_address 0.0.0.0` (trailing space, conf:23), `domain_delimiter @`, `map_library /usr/lib64/libperditiondb_posix_regex.so.0.0.0` + `map_library_opt /var/perdition/popmap.re` (conf:32-33, full path required per inline comment), `no_lookup` (conf:36), `ok_line "Reverse-proxy IMAP4S service lookup OK!"` (conf:39), `outgoing_server localhost` (conf:43), `strip_domain remote_login` (conf:46), `ssl_no_cert_verify` + `ssl_no_cn_verify` (duplicated, conf:51,54), `ssl_cert_file /etc/perdition/crt.pem`, `ssl_key_file /etc/perdition/key.pem` (conf:58-59).
- `services/imap4.service` → `/etc/systemd/system/imap4.service`: Type=forking, `perdition.imap4 --protocol IMAP4 --ssl_mode tls_outgoing --bind_address 127.0.0.1` (imap4.service:10 — loopback only, overrides conf bind_address).
- `services/imap4s.service` → `/etc/systemd/system/imap4s.service`: `perdition.imap4s --protocol IMAP4S`.
- `services/pop3s.service` → `/etc/systemd/system/pop3s.service`: `perdition.pop3s --protocol POP3S`.
- All three use `PIDFile=/var/run/perdition/perdition-<name>.pid` and `EnvironmentFile=-/etc/sysconfig/perdition`.

## State touched
- Host files: `/etc/perdition/perdition.conf`, `/etc/perdition/popmap.re` (seeded, unused), `/etc/perdition/crt.pem` + `key.pem` (via `install_service_hostcertificate`), `/var/perdition/popmap.re` (live map, rewritten on every regenerate), `/var/run/perdition/` pid dir.
- systemd: `imap4.service`, `imap4s.service`, `pop3s.service` in `/etc/systemd/system/` (RPM copies under `/usr/lib/systemd/system/` are deleted, install_perdition.sh:35); symlinks in `/etc/srvctl/system/` via `add_service`; the three services restarted on every container regenerate.
- Container rootfs (mail template only): `/etc/firewalld/services/*.xml` + enabled services imap/imaps/pop3s inside `$rootfs_base` (via mkrootfs_fedora hook).
- Firewall (host): `imaps`, `pop3s` services in default zone.
- Datastore: reads `$SC_DATASTORE_DIR/containers.json` (read-only; via `modules/datastore/lib.js`).
- Network: listens on 993 (imap4s), 995 (pop3s) on all interfaces, 143 (imap4) on 127.0.0.1; proxies outbound to `mail.<domain>` containers / `localhost`.

## Dependencies
- Core helpers: `msg`, `err`, `ntc`, `exif` (lablib.sh:131), `run_hook`/`run_hooks` (commonlib.sh:85,110), `load_libs`.
- Other modules: **containers** (module condition sourced verbatim; regenerate/mkrootfs hooks are containers-driven), **datastore** (`modules/datastore/lib.js`, `SC_DATASTORE_DIR` env), **firewalld** (`firewalld_add_service`, `firewalld_offline_add_service`), **certificates** (`install_service_hostcertificate`), **srvctl** (`sc_install`, `add_service`, `msg_version_installed` from fedoralib.sh/systemdlib.sh). Implicitly assumes the **postfix**/mail-container setup providing dovecot in `mail.*` containers and DNS resolution of `mail.<domain>`.
- External binaries: `node` (`/bin/node`), `dnf` (via sc_install), `systemctl`, `firewall-cmd`/`firewall-offline-cmd`, `chroot`, perdition package (`/usr/sbin/perdition.imap4|imap4s|pop3s`, `/usr/lib64/libperditiondb_posix_regex.so.0.0.0`).
- Node requires resolve relative to the module dir: `../../lablib.js` = install-root `lablib.js`, `../datastore/lib.js`.

## Bugs & smells
- **high** `hooks/update-install-host.sh:3` — the only call to `install_perdition` is commented out (done in commit e179f53 when the code moved to `libs/install_perdition.sh`), so `sc update-install` no longer installs perdition, its certs, `/var/perdition`, or the three units on a fresh host. Concrete harm: on such a host the perdition module is still active, and `hooks/regenerate.sh:3` → `perdition.js:82` fails writing `/var/perdition/popmap.re` (ENOENT) → exit 111 → `exif` in `libs/bashlib.sh:9` aborts the entire command — every `add-ve`/`regenerate` dies mid-flight.
- **medium** `hooks/version.sh:3` — `msg_version_installed Pound` queries the wrong package (copy-paste from the retired pound module); would report Pound's version or "Pound not installed" instead of perdition. Additionally the `version` hook is never triggered (`modules/srvctl/commands/version.sh` has no `run_hooks version`; no `run_hook version` exists in the tree), so perdition is silently missing from `sc version` output.
- **medium** `conf/perdition.conf:36` — `no_lookup` per perdition(8) disables map lookup and relays every user to `outgoing_server localhost` (conf:43), contradicting the `map_library`/`map_library_opt` popmap machinery at conf:32-33 that the whole module exists to feed. Either the generated popmap is ignored at runtime (all mail routing silently goes to localhost) or the option is dead weight; must be verified against a live host before any rewrite touches it.
- **low** `hooks/firewalld.sh:7` — the `${container:0:5} == "mail."` branch is dead: the only trigger path is `run_hooks firewalld` from the firewalld module's update-install hooks, where `$container` is unset (host context; inside a VE the perdition module is inactive). Even if it fired, opening the `imap` service is pointless because `services/imap4.service:10` binds 127.0.0.1 only.
- **low** `libs/install_perdition.sh:24` — seeds `/etc/perdition/popmap.re`, but `conf/perdition.conf:33` points `map_library_opt` at `/var/perdition/popmap.re`; the /etc file is never read or updated, misleading operators debugging routing.
- **low** `libs/install_perdition.sh:35` — `rm -fr` of RPM-owned unit files under `/usr/lib/systemd/system/`; any perdition package update restores them (harmless only because /etc units take precedence, but rpm -V breakage and confusion).
- **low** `perdition.js:79` — domain is interpolated into the regex unescaped, so `.` matches any character (`(.*)@example.com` also matches `user@exampleXcom`); duplicate identical lines are emitted when both `example.com` and `mail.example.com` containers exist. Also maps every container (including pure web sites) to a possibly nonexistent `mail.<domain>` backend.
- **low** `perdition.js:5-11,21-64` — most of the file is dead code: `ntc/get/run/rok` imports, `CMD/SRVCTL/SC_UID0/HOSTNAME/localhost`, `hosts/users/resellers/user/container`, `out()/return_value()/output()` are all unused; `process.exitCode = 99` (perdition.js:30) is the sentinel if the async callback never runs.

## Polish risks
- popmap line format `(.*)@<dom>: <mx>\n` and target path `/var/perdition/popmap.re` (perdition.js:79,82) — perdition's posix_regex map parses exactly this.
- Success message `datastore -> perdition popmap.re` via lablib.js `msg` (perdition.js:85); error prefix `DATA-ERR R:` with exit 111 (perdition.js:45-47); default exit 99, empty-value exit 100 (perdition.js:30,37); datastore `LIB-ERROR:` exit 112.
- `perditioncfg` failure string `PERDITION-ERROR cfg $* ($?) $__result` and the fact that it echoes node's combined stdout+stderr on success (libs/bashlib.sh:8-11); callers rely on `exif` aborting the whole srvctl run on node failure.
- `hooks/regenerate.sh:7` must keep ending in `return 0` — without it a failed `systemctl status` inside `restart_perdition` (systemdlib.sh:14,26,38 non-zero for dead units) would trip `exif` in `run_hook` (commonlib.sh:104) and abort regenerate.
- Unit names `imap4.service`, `imap4s.service`, `pop3s.service` installed to `/etc/systemd/system/` (install_perdition.sh:37-39) and enabled via `add_service` symlinks in `/etc/srvctl/system/`; `imap4` must keep `--ssl_mode tls_outgoing --bind_address 127.0.0.1` (services/imap4.service:10); PID files under `/var/run/perdition/` (all three units:8).
- `/etc/perdition/perdition.conf` exact directives, incl. `ok_line "Reverse-proxy IMAP4S service lookup OK!"` (conf:39 — visible to mail clients), full-path `map_library /usr/lib64/libperditiondb_posix_regex.so.0.0.0` (conf:32 — the .so.0 symlink does NOT work per conf:31), `domain_delimiter @`, `strip_domain remote_login`, `outgoing_server localhost`, cert paths `/etc/perdition/crt.pem|key.pem` (conf:58-59, produced by `install_service_hostcertificate /etc/perdition`).
- Restart status strings `restarted imap4s.service` / `imap4s restart FAILED!` (systemdlib.sh:11-13 and siblings; note the pop3s failure message says `pop3` not `pop3s`, systemdlib.sh:37).
- Host firewall services `imaps` and `pop3s` added on update-install (hooks/firewalld.sh:3-4); mail rootfs gets imap+imaps+pop3s offline (hooks/mkrootfs_fedora.sh:3-8 keyed on `rootfs_name == mail`).
- Module activation must stay identical to the containers module (module-condition.sh:3).

## v4 notes
- `perdition.js` is a one-function script drowning in copy-pasted datastore-module boilerplate (unused CMD/exit plumbing shared with `modules/datastore/*.js` siblings); in v4 this collapses into a ~10-line `.mjs` (or a template call) that maps `Object.keys(containers)` → popmap lines. The `msg/err/exit-code` protocol (0/99/100/111/112) is a farm-wide convention worth centralizing once in a v4 lablib.mjs.
- The install/regenerate/restart trio (`install_X`, `Xcfg`, `restart_X`) is the same shape as postfix/opendkim/saslauthd/haproxy modules — a generic v4 "service module" base (install package → install certs → render conf → manage units → regenerate on datastore change) would eliminate most of this module.
- Decide deliberately whether `install_perdition` returns to `update-install-host` or perdition is retired (the no_lookup contradiction, the pound leftover, and the disabled install suggest the module is half-abandoned); either way the regenerate hook needs a guard (`[[ -d /var/perdition ]] || return 0` equivalent) so an uninstalled perdition can't abort container provisioning.
- `restart_perdition` is 3x duplicated code — loop over unit names; the per-unit `is-active` check pattern also exists in other modules and belongs in a shared helper.
- The `version` hook mechanism is dead tree-wide; v4 should either wire `run_hooks version` into the version command or drop the per-module version hooks.
