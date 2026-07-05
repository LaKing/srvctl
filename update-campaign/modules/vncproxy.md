# vncproxy — v3 fact sheet (commit 988c38c)

## Purpose
Password-routed VNC gateway for the container farm. A vendored C++ proxy (`/bin/vncproxy`) listens on `$SC_HOST_IP:5900`; each VNC client authenticates with an 8-char "forward key" that the proxy looks up in a sqlite DB to pick the destination `<container>:5900`. The srvctl side of the module: one command (`add-vnc-user`) that registers a vnc user for a container in the datastore, a Node script that regenerates the routing records from `containers.json` (deriving deterministic passwords via a custom hash), a `start.sh` that rebuilds the sqlite DB from those records and execs the proxy, and a watchdog script that restarts the service when port 5900 stops answering VNC auth.

## Activation
`modules/vncproxy/module-condition.sh:3` simply sources `modules/containers/module-condition.sh` — i.e. the module is enabled exactly when the containers module is: on a real (non-container, non-`localhost.localdomain`) host that has `$SC_HOSTNET` or `/etc/srvctl/data`, and whose `$HOSTNAME` appears in `/etc/srvctl/hosts.json`; also forced true during `update-install ARG`. Conditions are evaluated in a subshell (`commonlib.sh:436`), so the `readonly SC_VIRT` inside the shared condition file is harmless.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| `add-vnc-user VE USERNAME` (`commands/add-vnc-user.sh`) | "Add user to the vnc server" | Host-only (`hs_only`, exit 44 off-host). Lowercases `$OPA` into `username`, regex-"validates" it (exit 22 with `Invalid username: $username` on failure — but see Bugs), runs `add container "$C" vncuser "$username"` (datastore; aborts via `exif` with `DATASTORE-ERROR …` if the container does not exist, exit 111), then `vncproxycfg "$C" "$username"` which regenerates `/var/vncproxy/records` for ALL containers and prints `User added. container: … vncuser: … host: … password: XXXXXXXX`. | `mkdir -p /var/vncproxy`; writes `vncusers` array in `containers.json`; rewrites `/var/vncproxy/records`; `systemctl restart vncproxy` + `systemctl status vncproxy --no-pager -n 30` (its exit code is the command's exit code). No `root_only` marker and no `authorize` call. |

There is no command to list or remove vnc users; removal requires manual datastore surgery.

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| - | - | Module has no `hooks/` directory. Notably nothing installs `services/vncproxy.service`, builds the binary, or installs the restarter timer — all provisioning is manual (see Bugs). |

## Libs
| function | file | notes |
|---|---|---|
| `vncproxycfg` | `libs/bashlib.sh:3-12` | Wrapper: runs `node $SC_INSTALL_DIR/modules/vncproxy/vncproxy.js $*` (word-split by design), `exif`-aborts on nonzero exit printing `VNCPROXY-ERROR cfg $* ($?) $result`, else echoes the node output. Loaded globally whenever the module is enabled (`commonlib.sh load_libs`); only caller in the repo is `add-vnc-user.sh:24`. Lacks the `[[ $SRVCTL ]] || exit 10` guard convention. |

Support scripts (not sourced libs):
- `vncproxy.js` — reads `datastore.containers`, builds one `record "KEY" "C:5900" "null" "USER @ C"` line per `(container, vncuser)` pair using `hash()` (`vncproxy.js:69-86`), async-writes them to `/var/vncproxy/records` (`vncproxy.js:100-105`), prints the `User added…` message. Requires `../../lablib.js` and `../datastore/lib.js` (path-relative, resolves under `$SC_INSTALL_DIR`). Exit codes: default 99 → 0 on success, 111 (`DATA-ERROR:`) on write failure.
- `start.sh` — service entry point: `mkdir -p /var/vncproxy`, deletes and recreates `/var/vncproxy/vncproxy.db` with schema `vncproxy(forward_key VARCHAR(8) PRIMARY KEY, dest_addr TEXT NOT NULL, dest_passwd VARCHAR(8), comment TEXT)` (`start.sh:13-20`), defines `record()` that string-interpolates into `INSERT` (`start.sh:23-25`), **bash-sources** `/var/vncproxy/records` (`start.sh:34`), sources `/etc/srvctl/host.conf`, runs `vncproxy $SC_HOST_IP:5900 $DBFILE` in the foreground, echoes `OK: vncproxy $SC_HOST_IP:5900` when the proxy exits.
- `vncproxy-restarter.sh` — nmap-probes port 5900 for "VNC Authentication"; on failure restarts+statuses the service. Lines 16-47 are commented-out systemd unit texts (`vncproxy-restarter.service`, `vncproxy-restarter.timer`, `OnCalendar=*:*:00` = every minute) plus install instructions — install is manual.
- `build.sh` — `cd vncproxy; ./waf configure; ./waf -v; rsync -av ./build/vncproxy /bin/vncproxy`. Manual, cwd-dependent, needs python.
- `dnf.sh` — `sudo dnf -y install sqlite sqlite-devel sqlite-tcl`. Manual; does not install nmap, gcc-c++, or python needed by the other scripts.

## Config & templates
- `services/vncproxy.service` — systemd unit (`Description=VNCProxy service.`, `ExecStart=bash /usr/local/share/srvctl/modules/vncproxy/start.sh`, `Restart=always`, `RestartSec=3`, `WantedBy=multi-user.target`). **Never referenced/installed by any script in the repo**; must be copied to `/etc/systemd/system` by hand.
- No `conf/` directory, no translations besides the `@en` help lines.

### Vendored third-party code (not audited line-by-line)
- `vncproxy/` (~6.7 MB) — "vncproxy" by Santa Zhang (santa1987@gmail.com), BSD-style LICENSE dated 2013 (`vncproxy/README`, `vncproxy/LICENSE`): C++ multi-threaded VNC proxy (`vncproxy.cc`, `d3des.c` DES for VNC auth) that routes by password using the sqlite schema above; binary usage `vncproxy <host:port> [proxy-db]` (`vncproxy.cc:565-599`), runs in the foreground. Bundled with a full waf distribution (its `README.md`/`ChangeLog` are waf 2.0.26's).
- `waf/` (~5.5 MB) — a second, standalone copy of the waf 2.0.26 build system (waf.io), including `demos/`, `playground/`, `tests/`. Only skimmed for provenance per the vendored-code rule.

## State touched
- Host paths: `/var/vncproxy/` (created 0755), `/var/vncproxy/records` (bash fragment with plaintext forward keys, default 0644), `/var/vncproxy/vncproxy.db` (sqlite, wiped and rebuilt on every service start, `start.sh:10`), `/bin/vncproxy` (installed by `build.sh:8`).
- systemd: `vncproxy.service` (restart in `add-vnc-user.sh:29`; unit hand-installed), optional hand-installed `vncproxy-restarter.service` + `.timer` (every minute).
- Datastore: `containers.json` → `containers[C].vncusers` (string array), written via `add container C vncuser NAME` (datastore `main.js:167-170`).
- Network: binds `$SC_HOST_IP:5900` (from `/etc/srvctl/host.conf`); forwards to `<container-name>:5900`, relying on host-side resolution of container names on the 10.x network.

## Dependencies
- Core: `err`, `exif` (`lablib.sh:131`), `hs_only` (containers module `libs/authlib.sh:3`, exit 44), datastore module (`add` in `modules/datastore/libs/bashlib.sh:95`, `modules/datastore/main.js`, `modules/datastore/lib.js`), `lablib.js` (`msg`/`err`), env `SC_INSTALL_DIR`, `SC_HOST_IP`, `SC_DATASTORE_DIR`.
- Modules assumed: containers (condition + authlib), datastore.
- External binaries: `node`, `sqlite3`, `systemctl`, `/bin/vncproxy` (self-built), `nmap` (restarter — not installed by `dnf.sh`), `rsync`+`python`+C++ toolchain (build only), `dnf`.

## Bugs & smells
- **HIGH `commands/add-vnc-user.sh:14`** — username regex `(([a-z]|[a-z_][a-z0-9_]{2,30}))` is unanchored, so any string containing a single lowercase letter passes (e.g. `x"; rm -rf / #`, spaces, quotes). The unvalidated name is stored in the datastore, interpolated by `vncproxy.js:95` into `/var/vncproxy/records`, which `start.sh:34` **sources as root bash** and `start.sh:24` splices into a raw sqlite `INSERT` — a crafted username yields root command execution / SQL injection at every service start; even benign odd names silently corrupt the records file.
- **MEDIUM `start.sh:37`** — `if [[ /bin/vncproxy ]]` tests a non-empty string literal, always true; the intended "binary exists" guard never guards. On a host where `build.sh` was never run, the service loops `bash: vncproxy: command not found`, prints the misleading `OK: vncproxy …:5900`, exits 0, and `Restart=always`/`RestartSec=3` crash-loops forever.
- **MEDIUM (security) `vncproxy.js:69-86,95` + `commands/add-vnc-user.sh`** — VNC passwords are a deterministic, non-cryptographic 8-char hash of (container-name, username), both effectively public (container names are domains). Anyone with the open-source algorithm can compute any user's VNC password offline; there is no salt, no rotation, and ≤32 bits of state per input string.
- **MEDIUM (security) `vncproxy.js:101`, `start.sh:5,13`** — `/var/vncproxy` is 0755 and `records`/`vncproxy.db` are written with default 0644, so every local user on the host can read all plaintext forward keys (the VNC passwords).
- **MEDIUM `services/vncproxy.service` (unreferenced) / `vncproxy-restarter.sh:16-47`** — no hook or command installs the service unit, builds the binary, or installs the restarter timer (grep: zero references outside the module; sibling modules like saslauthd/sshpiperd install units via `update-install-host` hooks). On any freshly provisioned host, `systemctl restart vncproxy` in `add-vnc-user.sh:29` fails: the module is not self-installing.
- **MEDIUM `vncproxy-restarter.sh:5`** — depends on `nmap`, which nothing installs (`dnf.sh:3` installs only sqlite). With the timer active and nmap missing (or the proxy momentarily busy), the grep never matches and the FAIL branch restarts vncproxy **every minute**, killing all live VNC sessions.
- **LOW `start.sh:15,24`** — `forward_key` is PRIMARY KEY and 8-char hash collisions between two (container,user) pairs are possible; the second `INSERT` fails, the sqlite3 error is unchecked, and that user silently loses access on every rebuild.
- **LOW (cross-module) `modules/datastore/main.js:157-174`** — duplicated `if (CMD === ADD)` blocks: `add container C vncuser U` triggers `write_containers()` twice (once before the vncuser is pushed, once after) — two concurrent async writes of different content to `containers.json`; if the stale write completes last, the just-added vncuser is lost.
- **LOW `vncproxy.js:112`** — `User added.` (and a `hash()` call) runs unconditionally; invoked with no args it throws `TypeError` on `s.length` inside `hash()` (undefined arg), so the script cannot be used standalone to merely regenerate records; dead imports (`hosts`, `users`, `resellers`, `use_codepad`, `out`, `CMD`) confirm it was cut down from a datastore clone.
- **LOW `commands/add-vnc-user.sh` (whole file)** — no `root_only` marker and no `authorize`; the command is hinted to all users on a host and a non-root run half-executes (datastore write may succeed, `systemctl restart` fails), leaving records and DB out of sync.

## Polish risks
A rewrite must preserve, byte-for-byte where stated:
- **The `hash()` algorithm** (`vncproxy.js:67-86`): the exact 77-char `chars` string, `Math.imul(h ^ charCode, 9 ** 9)` loop with seed 9, `Math.abs(h ^ (h >>> 9)).toString(10).padStart(10,"0")`, the overlapping substrings (0-3, 2-5, 4-7, 6-9) mod `chars.length`, join + `substring(0,8)`. Any change invalidates every deployed VNC password.
- Records file path `/var/vncproxy/records` and exact line format `record "KEY" "C:5900" "null" "USER @ C"` (`vncproxy.js:95`) — it is executed as bash by `start.sh:34` and may also be hand-edited on servers (`start.sh:28-30` shows the documented manual format).
- DB path `/var/vncproxy/vncproxy.db` and schema `vncproxy(forward_key VARCHAR(8) PRIMARY KEY, dest_addr TEXT NOT NULL, dest_passwd VARCHAR(8), comment TEXT)` (`start.sh:13-20`) — the vendored C++ binary reads exactly this (`vncproxy/README`).
- Binary path `/bin/vncproxy` (`build.sh:8`) and its CLI `vncproxy <host:port> [db]`; bind address `$SC_HOST_IP:5900` (`start.sh:40`); destination form `<container>:5900`.
- Unit name `vncproxy.service` with `ExecStart=bash /usr/local/share/srvctl/modules/vncproxy/start.sh`, `Restart=always`, `RestartSec=3` (`services/vncproxy.service:6-9`); hand-installed units reference `/usr/local/share/srvctl/modules/vncproxy/vncproxy-restarter.sh` (`vncproxy-restarter.sh:23`) — path changes break deployed units.
- Command name `add-vnc-user`, its `## @@@ / @en / &en` help block (`commands/add-vnc-user.sh:3-6`), exit 22 + `Invalid username: $username` (`:16-17`), `hs_only` gating (exit 44), final exit code = `systemctl status` result (`:30`).
- Operator-visible outputs: `User added. container: C vncuser: U host: H password: XXXXXXXX` (`vncproxy.js:112` — the only place the password is ever shown), `wrote vncproxy conf` (`vncproxy.js:103`), `OK: vncproxy IP:5900` (`start.sh:43`), `OK:`/`FAIL: nmap -p 5900 …` (`vncproxy-restarter.sh:7,9`), `VNCPROXY-ERROR cfg …` (`libs/bashlib.sh:9`), `DATA-ERROR:` exit 111 (`vncproxy.js:45-49`).
- Datastore key `containers[C].vncusers` (array of strings) and the `add container C vncuser NAME` verb.
- Global function name `vncproxycfg` (`libs/bashlib.sh:3`) — loaded into every srvctl shell when the module is on.

## v4 notes
- `vncproxy.js` is ~80% dead code copied from datastore tooling (unused `hosts/users/resellers/use_codepad/out/CMD`, `return_value/output` helpers); the live core is ~25 lines (hash + records loop + writeFile). In v4 this collapses into a small `.mjs` that imports a shared datastore API and a shared `hash()` util (candidate for a core `lib/hash.mjs` — but frozen algorithm, see Polish risks).
- Eliminate the bash-sourced `records` intermediary: v4 can write the sqlite DB (or a JSON the proxy reads) directly from the datastore, removing the root-bash-injection surface and the `start.sh` rebuild dance. Quote/parameterize SQL if sqlite stays.
- Make the module self-installing like saslauthd/sshpiperd: an `update-install-host` hook to install `vncproxy.service` (+ optional restarter timer), and declare `nmap`/toolchain deps; or replace the hand-rolled watchdog with systemd `WatchdogSec`/healthcheck.
- Reconsider shipping ~12 MB of vendored waf 2.0.26 (twice!) and a 2013 unmaintained C++ proxy in the srvctl tree; candidates: pre-built package, separate repo/submodule, or a maintained alternative (websockify/noVNC-style) — functionality must stay identical through the polish phase, so this is Phase-B material.
- Missing lifecycle pieces to design in v4: `remove-vnc-user`/`list-vnc-users`, per-user password rotation (requires abandoning the deterministic hash — breaking change to plan explicitly), and file permissions (0700 dir / 0600 files) for the secrets.
- Fix the datastore double-`ADD`/double-write race (`modules/datastore/main.js:157-174`) in the datastore rewrite; vncproxy's `add` flow is a direct victim.
