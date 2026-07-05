# usersonhost — v3 fact sheet (commit 988c38c)

## Purpose
Manages Unix user accounts on **host** (container-farm) machines: creating cluster users
and resellers in the datastore, provisioning the corresponding system accounts, generating
their passwords / SSH keys / client certificates, wiring reseller→user key links, and
bind-mounting each container's rootfs into its owning users' home directories (the
"share" mounts). The heavy lifting is done in Node (`main.js`, run via the `userscfg`
lib wrapper); the bash commands are thin front-ends that write to the datastore and then
trigger a regenerate. It also installs a set of host "user tools" (vnc, firefox, etc.) and
the srvctl sudoers file during host update-install.

## Activation  (module-condition.sh logic — when is this module enabled)
`module-condition.sh` simply `source`s `modules/containers/module-condition.sh` and inherits
its verdict. That means usersonhost is enabled (SC_USE_USERSONHOST=true) exactly when the
**containers** module is: i.e. the machine is a real host (not `localhost.localdomain`), is
**not** itself a systemd-nspawn/lxc container, has `$SC_HOSTNET` set or `/etc/srvctl/data`
present, and appears in `/etc/srvctl/hosts.json` — or the command is `update-install <arg>`.
Net effect: this module runs on cluster hosts, never inside containers.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| `add-user USERNAME` (commands/add-user.sh) | Add user to the current cluster | `reseller_only`; `sudomize`; lowercases ARG; validates against `[a-z_][a-z0-9_]{2,30}` (unanchored); if user doesn't already exist in datastore calls `new user "$username"` then `regenerate_users`; prints the reseller. | Writes users.json (via datastore `new`), triggers `userscfg`/main.js which creates the system account, keys, cert, password, bind mounts. |
| `add-reseller USERNAME` (commands/add-reseller.sh) | Add user as reseller to the host cluster | `root_only`; `sudomize`; same regex validation; if not existing calls `new reseller "$username"` then `regenerate_users`; errors if user exists. | Writes users.json with a reseller_id; regenerates as above. |
| `add-publickey [KEY|FILE]` (commands/add-publickey.sh) | Add an ssh publickey to the current cluster | `sudomize`; target file `$SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub`; with no arg opens `mcedit` then `return`; if ARG is a file `cat`s it, else appends `$OPAS`; removes file if empty; verifies with `ssh-keygen -l`, and on failure tries `ssh-keygen -i` conversion. | Writes/creates a `.pub` file in the caller's datastore user dir; may run mcedit interactively; may delete the file. |
| `change-user VE USERNAME` (commands/change-user.sh) | Move container to a different user | `reseller_only`; `sudomize`; validates the new username exists and reports its reseller — then prints `err "DEV (not implemented - yet.)"`. | None (stub; not implemented). |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| hooks/regenerate.sh | `regenerate` (fired by `containers/commands/regenerate.sh` → `run_hook regenerate`) | Calls `userscfg` → runs `main.js` with no args: reconciles all users, keys, certs, passwords and container share mounts on this host. |
| hooks/update-install-host.sh | `update-install-host` (fired from `srvctl/commands/update-install.sh:83` `run_hooks update-install-host`) | Installs sudo and writes `/etc/sudoers.d/srvctl` (NOPASSWD for `srvctl.sh *`); installs user tools: tigervnc-server, hg, fdupes, mailx, ratpoison, firefox, ShellCheck, p7zip-plugins (each guarded by a `/usr/bin/*` existence check). `return 0`. |

## Libs
- `libs/bashlib.sh`:
  - `userscfg` — `node main.js $*`. **Used** by regenerate hook and by `regenerate_users` (userlib).
  - `usercfg` — `mkdir ~/.srvctl`, `node user.js $*`, then sources `~/.srvctl/user.conf`. **No caller anywhere in the repo** (dead; see Bugs).
- `libs/userlib.sh`:
  - `create_user_id(user)` — bash path that `adduser`s + calls `crate_user_password`, `create_user_ssh` (ssh module), `create_user_client_cert`. **Only referenced from the dead tail of `regenerate_users`.**
  - `crate_user_password(user)` (bash) — sic typo; writes datastore `.password` and pipes to `passwd --stdin`. Only reachable from the dead path.
  - `regenerate_users()` — logs, calls `userscfg`, then `return`; everything after the `return` (the per-user loop) is unreachable. **Called by** add-user.sh, add-reseller.sh, and `containers/commands/add-ve-user.sh`.
- `main.js` provides internal JS reimplementations (`crate_user_password`, `create_user_ssh`,
  `create_user_client_cert`, `make_share`, `make_share_mount`) — none exported; it is a script,
  not a module.
- `user.js` — standalone script writing `~/.srvctl/user.conf` from `users.json[SC_USER]`.

## Config & templates (conf/ contents and where they get installed)
No `conf/` directory. The only file this module installs is `/etc/sudoers.d/srvctl`
(generated inline in hooks/update-install-host.sh, not from a template).

## State touched
- Host paths:
  - `/etc/sudoers.d/srvctl` (created/overwritten).
  - `$SC_DATASTORE_DIR/users/<user>/` — `.password`, `.hash`, `id_ecdsa[.pub]`,
    `srvctl_id_ecdsa[.pub]`, `reseller_id_ecdsa.pub` + `srvctl_reseller_id_ecdsa.pub`
    (symlinks), `<SC_USER>-<NOW>.pub` (add-publickey).
  - `users.json` (via datastore `new user`/`new reseller`).
  - System accounts via `adduser` (uid taken from datastore `users[u].uid`).
  - `/home/<user>/.password` (plaintext), `/home/<user>/.ssh/id_ecdsa[.pub]`,
    `/home/<user>/<user>@<SC_COMPANY_DOMAIN>.p12`, and per-container share dirs
    `/home/<user>/<container>/{bindfs,html}`.
  - CA p12 read from `/etc/srvctl/CA/usernet/client-<user>.p12`.
  - `~/.srvctl/user.conf` (user.js, if ever invoked).
- Container/remote paths: bind sources `/srv/<c>/rootfs` (local) or
  `/var/srvctl3/nfs/<host>/srv/<c>/rootfs` (remote, requires NFS+OpenVPN).
- systemd units: none directly.
- Network: relies on OpenVPN mesh + NFS for remote-host share mounts; may `ssh $SC_ROOTCA_HOST`
  to mint client certs.
- Installed packages: tigervnc-server, hg, fdupes, mailx, ratpoison, firefox, ShellCheck,
  p7zip-plugins, sudo, bindfs (bindfs installed by the sshpiperd module, not here).

## Dependencies
- Core helpers: `msg`/`ntc`/`err`/`debug`, `run`/`nur`, `exif`, `sudomize`, `root_only`,
  `reseller_only`, `argument` (authlib), `sc_install`/`sc_update` (fedoralib), datastore
  `new`/`get`, `new_password` (password module), `run_hook`/`run_hooks`, `load_libs`.
- Node deps: `../datastore/lib.js` (hosts/users/resellers/containers, `container_uid`,
  `container_host`), `../password/lib.js` (`get_password`), `../../lablib.js`
  (`msg/ntc/err/get/run/rok/exec_function`).
- Cross-module functions assumed present at regenerate time: `create_ca_certificate`,
  `ca_sync` (ca module) via `exec_function`; `create_user_ssh`/`create_user_client_cert`
  in the dead bash path reference ssh/certificates modules.
- Env: `NOW`, `SC_DATASTORE_DIR`, `SC_COMPANY_DOMAIN`, `SC_ROOTCA_HOST`, `SC_USER`, `SC_HOME`,
  `SC_INSTALL_DIR`, `SC_DATASTORE_RO`.
- External binaries: node, adduser, passwd, ssh-keygen, openssl, bindfs, getent, mount,
  mcedit, ssh, dnf.

## Bugs & smells
- **[high] add-publickey.sh:51** — `run ssh-keygen -i -f "$pub.tmp" > "$pub"` redirects the
  *whole* `run` invocation's stdout into `$pub`. `run` first `echo`s a colored command banner
  to stdout (lablib.sh run()), so `$pub` gets the ANSI banner line prepended to the converted
  key, corrupting the key file; the subsequent `ssh-keygen -l -f "$pub"` (line 60) then fails
  and the key is deleted. The RFC4716→OpenSSH conversion path is effectively broken.
- **[high] main.js:90** — `msg("Password-update for user: " + user + " password: " + password)`
  prints the user's **plaintext password** to stdout (and thus into srvctl logs / terminal)
  every time a password changes. The equivalent bash line (userlib.sh:49) is commented out;
  the active JS path leaks it. Sensitive-data disclosure.
- **[medium] add-user.sh:16 / add-reseller.sh:16** — username regex
  `[[ "$username" =~ ([a-z_][a-z0-9_]{2,30}) ]]` is **unanchored** (no `^…$`), so any string
  merely *containing* a 3+ char valid substring passes (e.g. `"!!!abc"`, `"a b user1"`).
  The unvalidated name then flows into `new user`/`new reseller` (datastore key) and later
  into `adduser`. Malformed/space-bearing usernames are accepted.
- **[medium] main.js:263-264** — `run("adduser -U -c '" + users[u].name + "' … " + u)`
  interpolates the datastore-supplied `name` (and reseller) into a shell single-quoted string
  with no escaping; a name containing `'` breaks quoting → shell command injection at
  regenerate time. Reseller-controlled input reaches a root shell.
- **[medium] libs/bashlib.sh:10 + user.js** — `usercfg`/`user.js` are **dead code**: `usercfg`
  has no caller anywhere in the tree. If ever re-enabled, user.js:43 `Object.keys(users[SC_USER])`
  throws for any SC_USER absent from users.json, and user.js:25 assigns an unused
  `SC_DATASTORE_DIR` from `SC_DATASTORE_RO`.
- **[medium] userlib.sh:55-74** — `regenerate_users()` executes `userscfg` then `return` at
  line 60; the entire per-user loop (61-73), and by extension `create_user_id` and the bash
  `crate_user_password`, are **unreachable dead code** that duplicates main.js logic and can
  drift from it.
- **[low] main.js:178-179 vs ssh/libs/userlib.sh:60-61** — divergent symlink names for the
  reseller srvctl key: main.js writes `srvctl_reseller_id_ecdsa.pub`, ssh/userlib writes
  `reseller_srvctl_id_ecdsa.pub`. Whichever path runs, consumers expecting the other name
  won't find it (no current consumer greps for either, so latent).
- **[low] main.js:113** — `fs.chmodSync(dir, 0600)` sets the datastore user directory to mode
  0600 (no execute/traverse bit) on every run. Root is unaffected, but any non-root reader
  (e.g. an `AuthorizedKeysCommand` user) cannot traverse it to reach the `*.pub` files.
- **[low] add-publickey.sh:35-40** — after removing an empty `$pub` (line 37), line 40
  `cat "$pub"` runs unconditionally → a stray "No such file" error on the empty-input path.
- **[low] add-publickey.sh:21** — `[[ -z $ARG ]] && [[ ! -f $ARG ]]` is redundant (when ARG
  is empty `-f ""` is already false); harmless but confusing.

## Polish risks
- Datastore layout and exact filenames must be preserved: `$SC_DATASTORE_DIR/users/<user>/`
  containing `.password`, `.hash` (sha512 hex of password, no salt/newline — main.js:98,103),
  `id_ecdsa[.pub]`, `srvctl_id_ecdsa[.pub]`, and the reseller symlinks `reseller_id_ecdsa.pub`
  / `srvctl_reseller_id_ecdsa.pub` (main.js:178-179). SSH key comments have the exact form
  `<user>@<SC_COMPANY_DOMAIN> (id_ecdsa <HOSTNAME> <NOW>)` and `(srvctl <HOSTNAME> <NOW>)`
  (main.js:120-156).
- add-publickey target path `$SC_DATASTORE_DIR/users/$SC_USER/$SC_USER-$NOW.pub` and the
  `$NOW` format `%Y.%m.%d-%H:%M:%S` (init.sh:60) — filenames embed colons.
- Client cert file placed at `/home/<user>/<user>@<SC_COMPANY_DOMAIN>.p12` sourced from
  `/etc/srvctl/CA/usernet/client-<user>.p12` (main.js:195,209).
- Share mount dirs `~/<container>/bindfs` (root uid) and `~/<container>/html` (root uid+48),
  skipping `html` for `mail.*` containers; bindfs flags `--mirror=<user>
  --create-for-user=<uid> --create-for-group=<uid>` and the mount-detection string
  `"<source> on <dir> type fuse"` (main.js:234,253-254).
- Exit codes: add-user/add-reseller `22` on invalid username; change-user `22` (no username),
  `23` (unknown user). Command help lines (`## @@@`, `## @en`, `## &en`), including the
  existing typos "argiument"/"publikkey" in add-publickey.sh:6,64 — visible in `srvctl man`.
- `/etc/sudoers.d/srvctl` exact contents: header `## srvctl v3 sudo file` and
  `ALL ALL=(ALL) NOPASSWD: $SC_INSTALL_DIR/srvctl.sh *` (update-install-host.sh:5-6).
- The installed user-tool package set and their `/usr/bin/*` guards (update-install-host.sh:14-33).

## v4 notes
- The active runtime is already JS (`main.js`). A `.mjs` port should absorb `add-user`,
  `add-reseller`, `add-publickey`, and the regenerate reconciliation, dropping the bash
  command shells and the `userscfg`/`usercfg` node-shell-glue in bashlib.sh.
- Delete the dead bash reconciliation: `usercfg`/`user.js`, `create_user_id`, bash
  `crate_user_password`, and the unreachable tail of `regenerate_users`. Keep a single
  reconcile implementation to stop bash/JS drift (symlink-name mismatch, password logic).
- Fix and fold together: unanchored username validation (share one anchored validator across
  add-user/add-reseller), shell-injection-safe `adduser` (pass args as an argv array, not an
  interpolated string), and stop logging plaintext passwords.
- Rework add-publickey to write with an explicit file target instead of relying on `run … >`
  redirection so the command banner can't leak into key files; consider dropping mcedit for a
  stdin/argument-only flow.
- Reconcile the two SSH-provisioning implementations (this module's main.js vs
  `modules/ssh/libs/userlib.sh`) into one; they duplicate key creation with subtly different
  filenames and permission handling.
- `change-user` is an unimplemented stub — either implement (IP/uid reassignment + container
  restart) or remove.
- Move hard-coded magic (`+48` apache uid, `mail.` prefix skip, the user-tools package list)
  into named config.
