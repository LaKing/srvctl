# codepad — v3 fact sheet (commit 988c38c)

## Purpose
Provisions "codepad" collaborative-development containers. The module (a) builds a dedicated
fedora-based template rootfs (`$SC_ROOTFS_DIR/codepad`) preloaded with a `codepad.service`
Node.js server stub, a git repo (`/var/git` bare + `/srv/codepad-project` clone), SSH keys and a
self-signed cert; (b) initializes each new codepad container (fresh SSH keys, uid-shifted chown,
boilerplate symlinks); (c) opens the codepad ports (tcp 9000/9001) in the host and template
firewalls; and (d) on every `regenerate`, publishes user credential files (`.hash`, `.password`,
`.ip`) from the datastore into `/var/srvctl3/share/containers/<C>/users/<u>/`, which is
bind-mounted read-only into every container so the in-container codepad server can authenticate
srvctl users. The codepad application itself is NOT in this repo — the generated
`/var/codepad/server.js` requires `./boilerplate`, symlinked from `/usr/local/share/boilerplate`
(itself a bind mount from a `v3-devel` container, see containers/libs/systemlib.sh:71-81).

## Activation
`modules/codepad/module-condition.sh` (evaluated in a subshell by `test_srvctl_modules`,
commonlib.sh:436; result cached in `/var/local/srvctl/modules.conf` as `SC_USE_CODEPAD`):
- echoes `false` when running inside a container (`systemd-detect-virt -c` = `systemd-nspawn`
  or `lxc`) or when `$HOSTNAME` starts with `mail.` (module-condition.sh:7-11);
- otherwise delegates by sourcing `modules/containers/module-condition.sh`
  (module-condition.sh:13), i.e. enabled exactly when the containers module is enabled: host is
  configured (`$SC_HOSTNET` set or `/etc/srvctl/data` exists), not itself a container, and
  `$HOSTNAME` appears in `/etc/srvctl/hosts.json` — or during `update-install <arg>`.
Net effect: enabled on configured container hosts, never inside containers, never on `mail.*` hosts.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| `add-codepad NAME` | "Add a fedora container with codepad preinstalled." (commands/add-codepad.sh:4) | Marked `## DEPRECATED` (line 9, comment only — still dispatched and listed in help). Rejects `mail.*` names (exit 13, line 11-15); requires name ending `-devel` (exit 13, line 17-21); `argument container-name; authorize; sudomize`; `add_ve codepad "$ARG"` (containers module; note: datastore records type `fedora` for codepad, addcontainerlib.sh:40-44, while the filesystem is instantiated from the `codepad` rootfs); `run_hook add-ve` (no module ships an `add-ve.sh` hook today → no-op); `run_hook regenerate` (all modules, incl. this module's own regenerate hook); `init_codepad_project "$ARG"`; `run_hook add_codepad_project` (no provider exists → no-op, and a duplicate: init_codepad_project already ran it). | Creates and starts an nspawn container (via add_ve: datastore entry, `/srv/NAME/*`, `srvctl-nspawn@NAME` enabled+started), then codepad project init (see Libs). |

The canonical creation path today is the generic `add-ve NAME codepad`
(containers/commands/add-ve.sh:37 `run_hook "add_ve_$T"` → this module's `add_ve_codepad` hook).
That path does NOT enforce the `-devel` name rule, even though haproxy only proxies ports
9000/9001/24678 to containers whose name contains `-devel` (haproxy.js:386-390).

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/add_ve_codepad.sh` | `run_hook "add_ve_$T"` after generic `add-ve NAME codepad` (containers/commands/add-ve.sh:37) | `init_codepad_project "$ARG"` (2-line file, no shebang/guard). |
| `hooks/firewalld.sh` | `run_hooks firewalld`, fired from firewalld module's update-install-host.sh:12 and update-install-ve.sh:12 | Opens host firewall services `http9000` (tcp 9000) and `https9001` (tcp 9001) via `firewalld_add_service`; writes `/etc/firewalld/services/{http9000,https9001}.xml` on the host. |
| `hooks/mkrootfs_fedora.sh` | `run_hooks mkrootfs_fedora` at end of `mkrootfs_fedora_base` (containers/libs/mkrootfs_fedora.sh:87), i.e. during every fedora-family rootfs build | Guarded `[[ $rootfs_name == codepad ]]` (`rootfs_name`/`rootfs_base` are locals of the calling function, visible because hooks are sourced). Uses `firewalld_offline_add_service` (chroot firewall-offline-cmd) to open http 80, https 443, http8080, https8443, https9200, https9000 (9000), https9001 (9001) inside the codepad template. Duplicates the firewalld module's own mkrootfs hook, which only handles `rootfs_name == fedora`. |
| `hooks/regenerate.sh` | `run_hook regenerate` (from `sc regenerate`, `add-ve`, `add-ve-user`, `add-codepad`, regenerate_all_hosts) | `configure_codepad_access` → `node access.js`: republishes all users' access-key files for all containers. |
| `hooks/regenerate_rootfs.sh` | `run_hook regenerate_rootfs` from `sc regenerate rootfs` (containers/commands/regenerate.sh:22) | `mkrootfs_fedora_install_codepad` — rebuilds the codepad template rootfs from scratch. Runs BEFORE the containers module's own hook (module glob order: codepad < containers). |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` from `sc update-install` (modules/srvctl/commands/update-install.sh:83) | `run dnf -y install gcc-c++` on the host (native node-module builds). |

## Libs
All sourced into the global shell when `SC_USE_CODEPAD=true`.

- `configure_codepad_access` (libs/configure_codepad_access.sh:3) — exports `SC_ROOTCA_HOST`
  (access.js never reads it), runs `/bin/node $SC_INSTALL_DIR/modules/codepad/access.js $*`,
  `exif "CODEPAD-ACCESS-ERROR cfg $* ($?)"` → any node failure aborts the whole srvctl run.
  Used only by this module's regenerate hook.
- `create_codepad_certificate rootfs` (libs/create_codepad_certificate.sh:3) — one-shot
  (guarded on key+crt existence) self-signed cert into template `/var/codepad/`:
  `localhost.key|csr|org.pem|crt` + `localhost-cert-config.txt`; CN/SAN = the build **host's**
  `$HOSTNAME`, 2048-bit, 365 days; key chmod 600, crt 644. Used only by
  `mkrootfs_fedora_install_codepad`.
- `init_codepad_project C` (libs/init_codepad_project.sh:3) — per-container init on the host:
  wipes and regenerates `/srv/$C/rootfs/var/codepad/.ssh` (ecdsa, no passphrase, comment
  `codepad@$C $NOW`); appends the pubkey to the container root's `authorized_keys`
  (codepad key = root SSH access inside the container, intentional for `-devel` containers);
  `chown -R $((C_uid+804))` of `/var/codepad` (uid-shift for nspawn PrivateUsers; 804 = codepad
  uid created in every fedora rootfs, containers/libs/mkrootfs_fedora.sh:65-66); symlinks
  `/var/codepad/users` → `/var/srvctl3/share/containers/$C/users` (host path, valid in-container
  via the `BindReadOnly` line emitted by datastore/lib.js:613); symlinks
  `/srv/codepad-project/@boilerplate` → `/usr/local/share/boilerplate/@boilerplate` if present;
  `run_hook add_codepad_project`. Used by the command and the `add_ve_codepad` hook.
- `mkrootfs_fedora_install_codepad` (libs/mkrootfs_fedora_install_codepad.sh:3) — builds the
  template: `mkrootfs_fedora_base codepad "systemd-container httpd mod_ssl gzip git-core curl
  python openssl-devel postgresql-devel mariadb-server ShellCheck make"`; creates
  `/var/codepad/.ssh`, `/srv/codepad-project`, `project.log`; mongod.service wants-symlink;
  cert; bare git repo `/var/git` + clone to `/srv/codepad-project`; `.gitconfig`
  (user `codepad`, email `codepad@$CDN`); default ecdsa key; `.profile` (`cd
  /srv/codepad-project` + `mc`); writes `codepad.service` (node `/var/codepad/server.js`, User/
  Group codepad, Restart=always, NODE_ENV=production) + wants-symlink; writes `server.js` stub
  (global `ß`, `ß.theme = "cobalt"`, `require("./boilerplate")`); symlinks
  `/var/codepad/@codepad-modules` and `/var/codepad/boilerplate` to `/usr/local/share/boilerplate/*`;
  chroot-chowns `/var/codepad`. Used only by the regenerate_rootfs hook.
- `access.js` (node, run by configure_codepad_access) — reads datastore via
  `modules/datastore/lib.js`; for every container copies files matching `*.hash`, `*.password`,
  `*.ip` (matches the dotfiles `.hash`/`.password`/`.ip` written by usersonhost:
  `''.split('.')[1]` trick, access.js:101/109/117) from `$SC_DATASTORE_DIR/users/<u>/` into
  `/var/srvctl3/share/containers/<c>/users/<u>/` for: every user with `access == "all"`,
  the container's primary `user`, each of `containers[c].users[]`, and the primary user's
  `reseller` (access.js:124-148). Skips `u === 'root'`. Creates missing dirs (incl. datastore
  user dirs). Exits 0 with message `codepad: user and users access keys configured`.

## Config & templates
No `conf/` directory. All templates are inline heredocs in
`libs/mkrootfs_fedora_install_codepad.sh` (codepad.service:68-86, server.js:90-114,
.gitconfig:50-56) and `libs/create_codepad_certificate.sh` (openssl req config:20-48). They are
installed into the template rootfs `$SC_ROOTFS_DIR/codepad` (default `/var/srvctl3/rootfs/codepad`,
containers/hooks/pre-init.sh:4) and thence copied into every new codepad container.

## State touched
- Host: `$SC_ROOTFS_DIR/codepad` (whole template rootfs, rebuilt by regenerate rootfs);
  `/etc/firewalld/services/http9000.xml`, `/etc/firewalld/services/https9001.xml` + firewalld
  runtime/permanent config; `gcc-c++` RPM installed; shell CWD left at
  `$SC_ROOTFS_DIR/codepad/var/git` after the rootfs hook (see Bugs).
- Datastore/share: `$SC_DATASTORE_DIR/users/<u>/` (created if missing);
  `/var/srvctl3/share/containers/<c>/` and `.../users/<u>/{.hash,.password,.ip}` for all
  containers (bind-mounted read-only into containers).
- Container rootfs (`/srv/<C>/rootfs` and template): `/var/codepad/*` (keys, cert, server.js,
  .profile, .gitconfig, project.log, users symlink, boilerplate symlinks), `/srv/codepad-project`
  (git clone + `@boilerplate` symlink), `/var/git` (bare repo), `/root/.ssh/authorized_keys`
  (codepad pubkey appended), `/etc/systemd/system/codepad.service` (+ multi-user wants symlink),
  mongod.service wants symlink, `/etc/firewalld/services/{http,https,http8080,https8443,https9200,https9000,https9001}.xml`.
- systemd units: `codepad.service` (in-container), dangling `mongod.service` symlink;
  container lifecycle units only via containers module.
- Network: host tcp 9000/9001 opened; template firewall 80/443/8080/8443/9200/9000/9001;
  haproxy (separate module) fronts 9000/9001 only when `SC_USE_CODEPAD=true` and only for
  `-devel`-named containers or `proxy_ports` entries (haproxy.js:64-65,386-390,483-503).

## Dependencies
- Core helpers: `msg`, `err`, `ntc`, `run` (lablib.sh:93 — executes `$*` unquoted in the current
  shell, warns via `eyif` on failure, does NOT exit), `exif` (exits with last status),
  `run_hook`/`run_hooks` (commonlib.sh:85-114), `get`, `NOW`, `SC_INSTALL_DIR`, `HOSTNAME`.
- Modules assumed: **containers** (`add_ve`, `mkrootfs_fedora_base` + its locals
  `rootfs_name`/`rootfs_base`, codepad user uid 804 in every fedora rootfs
  (mkrootfs_fedora.sh:65-66), `SC_ROOTFS_DIR`, nspawn config incl. boilerplate bind
  systemlib.sh:71-81); **firewalld** (`firewalld_add_service`,
  `firewalld_offline_add_service`); **datastore** (node `lib.js`, bash `new`/`get`,
  `SC_DATASTORE_DIR`, `BindReadOnly=/var/srvctl3/share/containers/<C>` lib.js:613, chown of
  `/srv/codepad-project` in restore-userids script lib.js:572); **srvctl**
  (`argument`/`authorize`/`sudomize`); **usersonhost** (producer of the `.hash`/`.password`/`.ip`
  files access.js consumes, usersonhost/main.js:94-104, userlib.sh:35-51); **haproxy**/**vncproxy**
  (consumers of `SC_USE_CODEPAD`); **ssh** module writes `.pub` keys into the same share tree.
- External binaries: `node`, `openssl`, `ssh-keygen`, `git`, `dnf`, `chroot`, `firewall-cmd`,
  `firewall-offline-cmd`, `systemd-detect-virt`.
- External artifacts (not in repo): `/usr/local/share/boilerplate` (`@boilerplate`,
  `@codepad-modules`, `boilerplate` — the actual codepad application), `/usr/local/share/codepad`.

## Bugs & smells
- **high** libs/../access.js:108-113 — copies each authorized user's plaintext `.password` file
  (which usersonhost also sets as the user's host login password, usersonhost/main.js:91-96)
  into `/var/srvctl3/share/containers/<c>/users/<u>/`, bind-mounted into container `c`; every
  process/user inside a shared devel container can read every other authorized user's (and any
  `access=all` admin's, and the reseller's) plaintext password. The `.hash` alone would suffice
  for codepad auth.
- **medium** libs/mkrootfs_fedora_install_codepad.sh:31 — `run chroot "$rootfs" chown
  codepad:codepad "$rootfs"/srv/codepad-project`: the path is host-absolute inside the chroot
  (doubled to `$rootfs$rootfs/...`), so the chown always fails (eyif warning only);
  `/srv/codepad-project` in the template stays root-owned and the codepad service cannot write
  its project dir until the in-container restore-userids/push scripts happen to fix it.
- **medium** libs/mkrootfs_fedora_install_codepad.sh:22-23 — on missing `$rootfs` after a failed
  `mkrootfs_fedora_base` (its dnf-failure path removes the dir and `return`s), the code does
  `err ...; exit` — bare `exit` inherits `err`'s status 0 (err ends in echo, lablib.sh), so
  `sc regenerate rootfs` terminates reporting success while the codepad image was not built.
- **medium** libs/mkrootfs_fedora_install_codepad.sh:47 — `git clone "$rootfs"/var/git
  "$rootfs"/srv/codepad-project -q` bakes the host template path
  (`/var/srvctl3/rootfs/codepad/var/git`) as the `origin` URL in every container's
  `/srv/codepad-project/.git/config`; inside a container that path does not exist, so push/pull
  to origin always fails (the intended in-container remote is `/var/git`, which also stays
  root:root-owned).
- **low** libs/mkrootfs_fedora_install_codepad.sh:52 — `email = codepad@$CDN`: `$CDN` is defined
  nowhere in the repo or example-conf, producing the malformed git identity `codepad@`.
- **low** libs/mkrootfs_fedora_install_codepad.sh:38 — mongod.service wants-symlink is created
  but no mongodb package is in the install list (line 10); dangling symlink, unit load errors at
  every container boot, and anything expecting mongo silently lacks it.
- **low** libs/mkrootfs_fedora_install_codepad.sh:45 — `run cd "$rootfs"/var/git` changes the
  srvctl process CWD and never restores it; every later hook in the same run (e.g. the containers
  module's own regenerate_rootfs hook, which runs next) executes from inside the codepad template.
- **low** libs/mkrootfs_fedora_install_codepad.sh:33 — `echo '# Init\n'` writes a literal `\n`
  into `project.log` (single quotes, no `-e`).
- **low** commands/add-codepad.sh:34 + libs/init_codepad_project.sh:34 — `run_hook
  add_codepad_project` is executed twice per add-codepad (once inside init_codepad_project, once
  by the command); latent double-execution the day any module ships that hook.
- **low** libs/create_codepad_certificate.sh:20 — heredoc appends (`>>`) to
  `localhost-cert-config.txt`; if the key exists but the crt is missing (partial previous run),
  the guard (line 17) re-enters and the config accumulates duplicate sections.
- **low** access.js:83-86 — as a side effect, creates empty `$SC_DATASTORE_DIR/users/<u>`
  directories for any referenced user (incl. resellers/`access=all` users) that has none —
  litter, and unexpected writes when `SC_DATASTORE_DIR` resolves to the read-only replica dir.

## Polish risks
- Exit codes: `exit 13` for both name-validation failures (commands/add-codepad.sh:14,20);
  access.js exit 0 on success / 111 `DATA-ERROR:` convention (access.js:51-55); exif aborts the
  whole run with node's code and message `CODEPAD-ACCESS-ERROR cfg  (…)`
  (libs/configure_codepad_access.sh:11).
- Exact error strings: "Adding codepad into a mail container is uncommon, and not suggested. I
  will stop for now." (add-codepad.sh:13); "We require codepad containers to use a *-devel name.
  Exiting for now." (add-codepad.sh:19); success line `codepad: user and users access keys
  configured` (access.js:163).
- Help text: `## @@@ add-codepad NAME`, `## @en Add a fedora container with codepad
  preinstalled.` and the two `## &en` lines (add-codepad.sh:3-6) must render identically.
- `-devel` suffix rule (add-codepad.sh:17) is load-bearing: haproxy gates ports 9000/9001/24678
  on `c.includes("-devel")` (haproxy.js:388).
- firewalld service NAMES are persisted as XML files on hosts/containers and rechecked by name:
  host `http9000`, `https9001` (hooks/firewalld.sh:4-5); template `http`, `https`, `http8080`,
  `https8443`, `https9200`, `https9000`, `https9001` (hooks/mkrootfs_fedora.sh:11-23). Note the
  9000 name differs host vs template (http9000 vs https9000) — preserve both.
- uid math `codepad_uid=$((C_uid + 804))` (init_codepad_project.sh:18) must stay in sync with
  `useradd -r -u 804 codepad` (containers/libs/mkrootfs_fedora.sh:65-66).
- Datastore type for codepad containers is `fedora`, not `codepad`
  (containers/libs/addcontainerlib.sh:40-44) — consumers key off this.
- Filesystem contract consumed by the out-of-repo codepad app and other modules: `/var/codepad`
  home, `/var/codepad/users` symlink → `/var/srvctl3/share/containers/$C/users`
  (init_codepad_project.sh:22; bind emitted by datastore/lib.js:613), credential filenames
  `.hash`/`.password`/`.ip` (access.js:101,109,117), `/srv/codepad-project`,
  `/srv/codepad-project/@boilerplate`, `/var/codepad/@codepad-modules`,
  `/var/codepad/boilerplate`, `/var/git`.
- `codepad.service` unit body (mkrootfs_fedora_install_codepad.sh:68-86): `ExecStart=/bin/node
  /var/codepad/server.js`, User/Group `codepad`, `Restart=always`, `Environment=NODE_ENV=production`.
- `server.js` stub semantics (mkrootfs...:90-114): `global.ß`, `ß.theme = "cobalt"`,
  `require("./boilerplate")` — the boilerplate app depends on the `ß` global and theme.
- `.profile` = `cd /srv/codepad-project` + `mc` (mkrootfs...:63-64); `.gitconfig` push.default
  simple (mkrootfs...:50-56); key type ecdsa, comment `codepad@$C $NOW`
  (init_codepad_project.sh:13); codepad pubkey appended to container root's authorized_keys
  (init_codepad_project.sh:15-16) — removing that breaks codepad-driven root ssh into its own
  container.
- Env contract: `SC_USE_CODEPAD` (from modules.conf) read by haproxy.js:65 and vncproxy.js:65;
  access.js reads `SC_DATASTORE_DIR`.
- recreate-ve relies on `/srv/$C/rootfs/srv/codepad-project/boilerplate/install.sh` existing in
  codepad containers (containers/commands/recreate-ve.sh:122-125).

## v4 notes
- access.js is 60% dead code (unused `CMD`, `SC_UID0`, `hosts`, `resellers`, `out`,
  `return_value`, `return_error`, `output`, exitCode-99 dance). The live logic is ~40 lines and
  is a near-duplicate of ssh module's ssh.js share-tree writer (ssh.js:83-97): v4 should have one
  `publish-user-credentials.mjs` used by both, copying only `.hash` (drop plaintext `.password`).
- Port lists are triplicated (hooks/firewalld.sh, hooks/mkrootfs_fedora.sh, firewalld module's
  own mkrootfs hook); v4: one declarative port manifest per module consumed by host/offline
  firewall code.
- Inline heredocs (unit file, server.js, .gitconfig, openssl config) belong in `conf/` template
  files with a sed_file/template step, like other modules.
- `add-codepad` is deprecated; the `add-ve NAME codepad` + `add_ve_$T` hook path already covers
  creation. v4: drop the command, move the `-devel` validation into the hook so both paths
  enforce it.
- The `if [[ $T == codepad ]] new container ... fedora` special case
  (containers/libs/addcontainerlib.sh:40-44) shows v3 conflates "rootfs image" with "container
  type"; v4 should model image and type as separate fields.
- Certificate creation duplicates containers' `create_selfsigned_domain_certificate`
  (addcontainerlib.sh:85+); the template cert has the build host's CN and is shared by all
  containers — regenerate per container (or drop; haproxy terminates TLS anyway).
- Magic uid 804 (and 801-803 in containers) should be named constants in one place.
- module-condition duplicates the in-container detection already inside the containers condition;
  it reduces to "containers enabled AND hostname not mail.*".
- The dangling mongod enablement and the unused `gzip`/`python` era package list need a
  deliberate re-decision rather than a carry-over.
