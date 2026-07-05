# module gui — v3 fact sheet (commit 988c38c)

## Purpose
Web GUI for srvctl: a root Node.js HTTPS daemon (`server.js`, port 250, systemd unit `srvctl-gui.service`) that authenticates browsers by TLS **client certificate** (CN = srvctl username, signed by the usernet CA), serves an Angular 1.x single-page app plus an hterm/wetty web terminal, and executes srvctl commands on hosts/containers **over ssh** using the user's internal key (`srvctl_id_ecdsa`). The bash side contributes one lib function, `make_commands_spec`, which compiles all command hints into `/var/local/srvctl/commands.spec` for the GUI's command menus.

**Key fact: the module is dormant in v3.** Its only hook is wrapped in `if false … fi` (hooks/update-install-host.sh:3-52), so nothing in this codebase ever installs the service, certificates, npm dependencies, or firewall rule. Only `make_commands_spec` is live (called from `sc update-install`, modules/srvctl/commands/update-install.sh:85-88). The daemon can only be running on hosts with leftover srvctl2-era setup.

## Activation
modules/gui/module-condition.sh:3-12: `SC_VIRT=$(systemd-detect-virt -c)`; echoes `false` if it reports `systemd-nspawn` or `lxc`, else `true`. So `SC_USE_GUI=true` on **every host** (and any non-container machine), cached in `/var/local/srvctl/modules.conf` by `test_srvctl_modules` (commonlib.sh:404-470, condition sourced in a subshell at commonlib.sh:436). No config toggle, no check that the GUI is actually installed.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | (module has no `commands/` directory) | - |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| hooks/update-install-host.sh | `update-install-host`, sourced by `run_hooks update-install-host` from `sc update-install` (modules/srvctl/commands/update-install.sh:83) | **Nothing** — entire body is inside `if false; then … fi` (lines 3-52). The dead code documents the intended install: remove old `/usr/lib/systemd/system/srvctl-gui.service` (l.7), `mkdir /etc/srvctl-gui` + `install_service_hostcertificate /etc/srvctl-gui` (l.9-10), heredoc `/etc/systemd/system/srvctl-gui.service` running `/bin/node $SC_INSTALL_DIR/modules/gui/server.js` as root (l.13-26), `daemon-reload`, `dnf install gcc-c++`, global `npm install -g` of node-pty, express, socket.io, ssh2, angular, bootstrap, angular-ui-bootstrap, angular-sanitize (l.36-44), enable+start the unit (l.46-48), `firewalld_add_service srvctl-gui tcp 250` (l.50) |

## Libs
libs/spec.sh (sourced by `load_libs` whenever `SC_USE_GUI=true`, i.e. on all hosts):
- `make_commands_spec_on_file <file>` (spec.sh:3-19) — skips files whose first 10 lines contain `root_only` or `## interactive` (l.5-6); extracts the `## @en` hint and the first `## @@@` syntax line; appends `path×command×hint×syntax` (`×` = U+00D7) to `/var/local/srvctl/commands.spec` (l.17).
- `make_commands_spec` (spec.sh:21-64) — **used cross-module**: called from modules/srvctl/commands/update-install.sh:87 under `if $SC_USE_GUI` (l.85). Rebuilds commands.spec from `/root/srvctl-includes/*.sh`, every `$SC_MODULES` dir's `commands/*.sh` (regardless of module enablement, l.30-36), every `/home/*/srvctl-includes/*.sh` (l.38-47), then appends raw `## spec` lines from enabled modules' `command.sh` (l.49-62; producers: modules/containers/command.sh:9-13, modules/srvctl/command.sh:18-22, format `## spec //cat×cmd×hint×args`).

Not sourced by bash but part of the module:
- `server.js` — the daemon (see Purpose); parses commands.spec (l.64-92), serves static app + npm globals (l.46-51), `/ssh/:user` → wetty.html (l.53-55), socket.io events `main`/`lock`/`terminal`/`command`/`get-main`/`output`/`input`/`resize`; `run_command` ssh-execs `command + ' 2>&1'` as the cert user (or root on containers) with the user's key (l.119-171); ANSI→HTML converter `term2html` (l.250-362).
- `srvctl-gui/` — Angular app (index.html/index.js/index.css/styles.css/scripts.js) and web terminal (wetty.html/wetty.js). `hterm_all.js` is **vendored** Chromium hterm/libdot (generated concat, 16k lines) — do not rewrite.
- `make_node_modules.sh` — manual helper to create a local node_modules; `package.json` — stale npm manifest (lists dead `pty.js`, not the `node-pty` the server uses).

## Config & templates
- No `conf/` directory. The systemd unit is heredoc'd inside the dead hook (hooks/update-install-host.sh:13-26); TLS material would be placed in `/etc/srvctl-gui/` by `install_service_hostcertificate` (modules/certificates/libs/servicecertlib.sh:3).

## State touched
- Writes: `/var/local/srvctl/commands.spec` (spec.sh:17,23 — `rm -fr` then append; root-owned, world-readable dir)
- (Dead code would write:) `/etc/srvctl-gui/{crt,key}.pem`, `/etc/systemd/system/srvctl-gui.service`, `/usr/lib/node_modules/*`, firewalld service `srvctl-gui` tcp/250
- server.js reads: `/etc/srvctl-gui/crt.pem`, `key.pem`, `/etc/srvctl/CA/ca/usernet.crt.pem` (l.28-34); `/var/srvctl3/datastore/{containers,users,hosts}.json` (l.59-61); `/var/local/srvctl/commands.spec` (l.65); `/var/srvctl3/datastore/users/<CN>/srvctl_id_ecdsa` (l.180)
- Network: HTTPS+websocket listen 0.0.0.0:250 (l.8,236); outbound ssh :22 to hosts and containers (l.162-168, 194)
- systemd unit `srvctl-gui.service` (legacy hosts only)

## Dependencies
- Core helpers: `msg` (lablib.sh:23) in spec.sh; `run` (lablib.sh:93) in the dead hook and in make_node_modules.sh; `run_hook`/`load_libs` dispatch (commonlib.sh:47-114); `HINT`/`HEMP` header constants (commonlib.sh:7,9)
- Other modules: **certificates** (`install_service_hostcertificate`, servicecertlib.sh:3), **firewalld** (`firewalld_add_service`, firewalldlib.sh:3) — both only in dead code; **ssh/usersonhost** must have created `users/<u>/srvctl_id_ecdsa` and authorized it on hosts/containers (modules/ssh/libs/userlib.sh:35, modules/usersonhost/main.js:137); **srvctl** module's update-install is the sole caller of `make_commands_spec`; **containers** datastore JSONs
- External: node, npm (globals in `/usr/lib/node_modules`: express, node-pty, socket.io@2, ssh2, angular, bootstrap, angular-ui-bootstrap, angular-sanitize), ssh client, gcc-c++ (node-pty build), systemd-detect-virt

## Bugs & smells
- **high** modules/gui/hooks/update-install-host.sh:3 — whole hook is `if false; then … fi`: the module can never be deployed from this codebase (no service, no certs, no deps, no firewall opening), yet `SC_USE_GUI=true` everywhere keeps spec.sh loading and `make_commands_spec` running on every `update-install` (update-install.sh:85-88). Dormant feature that still costs work and confuses audits; server only runs on hosts with srvctl2 leftovers pointing at current `server.js`.
- **medium** modules/gui/server.js:189 — `socket.request.headers.referer.split('/')[3]` with no guard: a socket.io connection without a `Referer` header (non-browser client, strict referrer policy) throws TypeError inside the `fs.readFile` callback → uncaught exception kills the whole daemon for all users.
- **medium** modules/gui/server.js:139 — `if (err) throw err;` inside the async `conn.exec` callback: any exec-channel failure crashes the entire server process.
- **medium** modules/gui/server.js:128-131 — `cmd.selected === 'container'` sets `user = "root"` and `host = cmd.container` from **client-supplied** data with no check that the container belongs to `socket.user` (the ownership filter exists only for display, l.108-110); authorization rests solely on whether the user's key happens to be accepted by `root@<target>` — the GUI happily attempts root ssh anywhere on the mesh on behalf of any cert holder.
- **medium** modules/gui/libs/spec.sh:30-36 — command scan iterates all `$SC_MODULES` without checking `SC_USE_*` (unlike l.49-62 which does), so commands of disabled modules end up in commands.spec and appear as GUI buttons that fail when clicked.
- **medium** modules/gui/server.js:12-13 — `SC_DATASTORE_DIR` and `SC_INSTALL_DIR` hardcoded (TODO acknowledged l.10-11); a non-standard install path breaks datastore reads and the category parser (l.80 depends on the `/usr/local/share/srvctl` prefix).
- **low** modules/gui/libs/spec.sh:11 — `head "$1" | grep -m 1 "$HEMP" "$1"`: because a file operand is given, grep ignores the `head` pipe and matches `## @@@` **anywhere** in the file; a stray `## @@@` deep in a script (heredoc, help text) becomes that command's GUI argument spec.
- **low** modules/gui/libs/spec.sh:10 — hint grep lacks `-m 1`: two `## @en` lines in a file's head would embed a newline in the spec record; the malformed continuation line makes `la[3].split` throw at server startup (server.js:84) — latent daemon-won't-start. (No current command file triggers it; verified across modules.)
- **low** modules/gui/server.js:59-61,92 — containers/users/hosts JSON and commands.spec are read once at startup into `const`s; new/removed containers and users are invisible in the GUI until the service is restarted.
- **low** modules/gui/server.js:167 — `readyTimeout: 500` (ms) for ssh connects; cluster hosts reached over the OpenVPN mesh routinely exceed this, yielding only "client-timeout error." in the terminal pane.
- **low** modules/gui/package.json:13 — depends on dead `pty.js@^0.3.1` while server.js:21 requires `node-pty`; `npm install` from this manifest builds the wrong (unbuildable on modern node) module. make_node_modules.sh:9 contradicts it.
- **low** modules/gui/make_node_modules.sh:7-13 — calls `run` but never sources lablib.sh and has no `[[ $SRVCTL ]]` guard; executed standalone every line fails with `run: command not found`, so it installs nothing.
- **low** modules/gui/server.js:347-361 — `term2html` HTML-escapes only text captured inside SGR color sequences; plain (un-colored) output containing `&ampersands` or `<tags>` reaches the client raw, relying entirely on Angular's ngSanitize (index.js:4, ng-bind-html index.html:99) to prevent markup injection, and garbling legitimate output containing `<`.
- **smell** modules/gui/libs/spec.sh:38-47 + server.js:95-114 — commands.spec includes every user's `~/srvctl-includes` commands and `send_main` ships the whole spec to every connected user: users see each other's private command names and hints.
- **smell** modules/gui/server.js:3,74 — `'use strict'` commented out; loop index `i` is an implicit global.
- **smell** modules/gui/server.js:51 — static mount `/wetty` from `/usr/lib/node_modules/wetty/public/wetty`, a package nothing installs and wetty.html doesn't use (it loads the module's own `/hterm_all.js`).

## Polish risks
A same-behavior rewrite must preserve exactly:
- Spec file path `/var/local/srvctl/commands.spec` and its record format: 4 fields joined by `×` (U+00D7), `sourcepath×command×hint×syntax` (spec.sh:17), consumed by server.js:64-92; plus the raw passthrough format `## spec //<cat>×<cmd>×<hint>×<args>` (spec.sh:59) whose leading `## spec //cat` makes `split('/')[2]` the category (server.js:81) — producers at modules/containers/command.sh:9-13 and modules/srvctl/command.sh:18-22.
- Exclusion rules: any file with `root_only` or `## interactive` in its first 10 lines is omitted from the spec (spec.sh:5-6).
- The fixed 7-character strips `${hintstr:7}` / `${hintcmd:7}` tied to the `## @en ` / `## @@@ ` prefixes (spec.sh:14-15; constants commonlib.sh:7,9) and `${command:0: -3}` stripping `.sh` (spec.sh:14 area, l.13).
- Function name `make_commands_spec` and its call site contract `if $SC_USE_GUI` (modules/srvctl/commands/update-install.sh:85-88); progress string "Make user commands spec for srvctl-gui." (spec.sh:22).
- Activation semantics: `SC_USE_GUI=false` only inside systemd-nspawn/lxc, `true` otherwise (module-condition.sh:6-12) — other code (update-install.sh:85) relies on the variable existing.
- Daemon contract (for legacy hosts): HTTPS port **250** (server.js:8); TLS client-cert auth with cert `/etc/srvctl-gui/crt.pem`, key `/etc/srvctl-gui/key.pem`, CA `/etc/srvctl/CA/ca/usernet.crt.pem`, `requestCert`+`rejectUnauthorized` (server.js:28-34); username = certificate CN (server.js:175-177).
- User key path `${SC_DATASTORE_DIR}/users/<CN>/srvctl_id_ecdsa` (server.js:180) — shared contract with ssh module (modules/ssh/libs/userlib.sh:35) and usersonhost (modules/usersonhost/main.js:137).
- Datastore reads `containers.json`, `users.json`, `hosts.json` under `/var/srvctl3/datastore` (server.js:12,59-61); container visibility filter `containers[i].user === socket.user` (server.js:108-110).
- Routes/events: `/ssh/:user` serves wetty.html (server.js:53-55); static mounts `/angular`, `/bootstrap`, `/angular-ui-bootstrap`, `/angular-sanitize`, `/wetty` from `/usr/lib/node_modules` (server.js:7,47-51); socket.io events `main`, `lock`, `terminal`, `command`, `get-main`, `output`, `input`, `resize` (server.js:95-233) — the shipped frontend hardcodes them (index.js:56-86, wetty.js:19-60).
- Execution semantics: command run via ssh as `<CN>@<host>` with ` 2>&1` appended (server.js:139); `localhost` mapped to the host's own hostname (server.js:127); container selection switches to `root@<container>` (server.js:128-131); interactive terminal spawns `ssh -p 22 -o PreferredAuthentications=publickey -i <keyfile> <user@host>` in a 80x30 xterm-256color pty (server.js:194-199).
- Unit/firewall names on legacy hosts: `srvctl-gui.service`, firewalld service `srvctl-gui` tcp 250 (hooks/update-install-host.sh:13,50).
- `srvctl-gui/hterm_all.js` is vendored generated code — keep byte-identical.

## v4 notes
- Decision needed first: **revive or retire**. The install path has been `if false` for the whole v3 line; if no production host still runs srvctl-gui, v4 should drop the daemon and keep only the machine-readable command spec (which is genuinely useful metadata).
- `server.js` is a natural `.mjs` rewrite candidate: take config from env (`SC_DATASTORE_DIR`, `SC_INSTALL_DIR`, port), local `node_modules` instead of `require('/usr/lib/node_modules/…')`, reload datastore/spec on change, guard the referer/exec error paths, validate container ownership server-side, and replace the AngularJS 1.x + Bootstrap 3 + socket.io v2 stack (all EOL).
- `make_commands_spec` quadruple-parses command headers that core already parses for help (`hint_on_file`, commonlib.sh:212; `hint_commands`, commonlib.sh:251): v4 should have one header parser emitting JSON once, consumed by both `sc help` and any GUI — replacing the fragile `×`-delimited format and the `## spec` passthrough hack.
- The heredoc-systemd-unit + `install_service_hostcertificate` + `firewalld_add_service` triple in the dead hook is the same pattern as postfix/perdition modules — one shared `install_service` helper in v4 core.
- `term2html` (server.js:250-362) is a hand-rolled partial ANSI→HTML converter; if the GUI survives, use the already-vendored hterm for everything and delete it.
