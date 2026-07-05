# postfix — v3 fact sheet (commit 988c38c)

## Purpose
Mail transport layer for the farm. On cluster hosts it installs and configures Postfix
(plus amavisd-new and spamassassin as content filter) as an SMTP/SMTPS relay hub:
TLS host certificate in `/etc/postfix`, custom `main.cf`/`master.cf`, `/etc/aliases`,
a `relaydomains` hash map generated from the datastore (all hosts + all containers +
their aliases), and firewalld openings for `smtp`/`smtps`. For containers it provides
the `ve-main.cf` template (relayhost = `srvctl-gateway`, Maildir delivery) that is
written into container rootfs both at base-image build time and at `add-ve` time, and
it restarts host postfix on every `regenerate`.

## Activation
`modules/postfix/module-condition.sh:3` sources
`modules/containers/module-condition.sh`, so postfix is enabled exactly when the
containers module is enabled:
- false if `HOSTNAME == localhost.localdomain` (containers/module-condition.sh:3-7)
- false inside a container (`systemd-detect-virt -c` is `systemd-nspawn` or `lxc`,
  containers/module-condition.sh:12-19) — despite comments in the libs about "inside containers"
- true if (`SC_HOSTNET` set or `/etc/srvctl/data` exists) and `$HOSTNAME` appears quoted
  in `/etc/srvctl/hosts.json` (containers/module-condition.sh:9,21-25)
- true during `sc update-install <ARG>` (containers/module-condition.sh:28-32)
- otherwise false

Result cached as `SC_USE_POSTFIX=true|false` in `/var/local/srvctl/modules.conf` /
`~/.srvctl/modules.conf` by `test_srvctl_modules` (commonlib.sh:404).

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | module has no `commands/` directory | - |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/update-install-host.sh` | `run_hooks update-install-host` from `sc update-install` (modules/srvctl/commands/update-install.sh:83) | `sc_install spamassassin postfix amavisd-new` (lines 7-9); `install_service_hostcertificate /etc/postfix` (line 12, certificates module — writes `crt.pem`/`key.pem`/optionally `ca-bundle.pem`, appends dhparam to crt); overwrites `/etc/postfix/main.cf` from `conf/hs-main.cf` (line 14); appends `smtpd_tls_CAfile =    /etc/postfix/ca-bundle.pem` if the bundle exists (lines 16-19); appends `smtpd_sasl_local_domain = $SC_COMPANY_DOMAIN` (line 21); overwrites `/etc/postfix/master.cf` from `conf/hs-master.cf` (line 23); `add_service postfix`, `amavisd`, `spamassassin` (lines 25-27: enable+restart+status, symlink in `/etc/srvctl/system/`); `make_aliases_db ''` → overwrites host `/etc/aliases` and runs `postalias` (line 29) |
| `hooks/regenerate.sh` | `run_hook regenerate` — from `sc regenerate` (containers/commands/regenerate.sh:30), `add-ve` (:38), `add-ve-user` (:37), `add-network-ve` (:47), `add-codepad` (:30), regenlib.sh:10 | `regenerate_etc_postfix_relaydomains` (rewrite `/etc/postfix/relaydomains` from datastore + `postmap`) then `restart_postfix` (full `systemctl restart postfix.service`) |
| `hooks/firewalld.sh` | `run_hooks firewalld` from firewalld module's update-install-host.sh:12 (and update-install-ve.sh:12, but SC_USE_POSTFIX is false in VEs) | `firewalld_add_service smtp` and `smtps` on the host (ports 25/465) |
| `hooks/mkrootfs_fedora.sh` | `run_hooks mkrootfs_fedora` from base-image build (containers/libs/mkrootfs_fedora.sh:87), `$rootfs_name`/`$rootfs_base` in scope | Only for `rootfs_name == "mail"`: `firewalld_offline_add_service smtp` + `smtps` inside the image via chroot `firewall-offline-cmd` |
| `hooks/version.sh` | **never fires** — no `run_hook version`/`run_hooks version` exists anywhere in the tree | would print `msg_version_installed postfix`; `sc version` instead hardcodes the same call (modules/srvctl/commands/version.sh:11) |
| `diagnose.sh` (module root, **not** in `hooks/`) | **never fires** — `run_hooks diagnose` (modules/srvctl/commands/diagnose.sh:91) only looks at `hooks/diagnose.sh` (commonlib.sh:97) | intended: `run openssl s_client -showcerts -connect localhost:465` and `run systemctl status amavisd.service --no-pager -n 30` |

## Libs
All sourced on every enabled run via `load_libs` (commonlib.sh:47-66).

| function | file | notes |
|---|---|---|
| `regenerate_etc_postfix_relaydomains` | `libs/postfixlib.sh:3-9` | If `/etc/postfix/` exists: `get cluster postfix_relaydomains > /etc/postfix/relaydomains` then `postmap` it. Data comes from datastore `cluster_postfix_relaydomains()` (modules/datastore/lib.js:935-958): every host, every container (with `mail.` prefix stripped), every container alias, one `<domain>\tOK` line each, deduplicated. Used only by this module's regenerate hook |
| `write_ve_postfix_conf <container>` | `libs/postfixlib.sh:11-25` | Pairs containers: for `mail.X` writes conf for `X` and `mail.X`; otherwise for `X` and `mail.X`. **Used by containers module** at `add-ve` (modules/containers/libs/addcontainerlib.sh:64) — public API surface |
| `write_ve_postfix_main <container>` | `libs/postfixlib.sh:28-64` | Silently returns if `/srv/$container` or its `rootfs/etc/postfix` is missing; if datastore says container exists, appends old `main.cf` to `main.cf-$NOW.bak` then overwrites it with `conf/ve-main.cf` (identical template for mail and non-mail; ve-mail.cf branch commented out at lines 55-60); else `err "$container dont exists"` |
| `write_postfix_main` | `libs/postfixlib.sh:67-90` | **Dead code** — no callers in the repo; commented "to be used inside containers" but the module is never enabled inside containers (see Activation). Would rewrite local `/etc/postfix/main.cf` from `ve-main.cf` and restart postfix |
| `make_aliases_db <rootfs>` | `libs/aliaseslib.sh:3-9` | Overwrites `$rootfs/etc/aliases` from `conf/aliases`, runs `postalias`. Only caller: this module's update-install-host hook with `''` (= host `/etc/aliases`). Not used at container build (containers/libs/mkrootfs_fedora.sh:75-77 edits the stock image aliases with `sed`/`newaliases` instead) |
| `restart_postfix` | `libs/systemdlib.sh:3-19` | `systemctl restart postfix.service`; if not active afterwards: `postfix check`, `err "Postfix restart FAILED!"`, `systemctl status` (exit 3 propagates — see Bugs). Used by regenerate hook and dead `write_postfix_main` |

## Config & templates
- `conf/hs-main.cf` → host `/etc/postfix/main.cf` (update-install-host.sh:14). Key content: `mynetworks = 127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 …` (:20), `relay_domains = $mydomain, hash:/etc/postfix/relaydomains` (:56), TLS via `/etc/postfix/crt.pem`/`key.pem` (:61-62,87-88), cyrus SASL (:67-71), `message_size_limit=26214400` (:76), amavis `content_filter=smtp-amavis:[127.0.0.1]:10024` (:79), opendkim milter `inet:127.0.0.1:8891`, `milter_default_action = accept` (:82-84), `lmtp/smtp_host_lookup = native` (:50-51), `compatibility_level = 2` (:5). `smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated` with `reject_unauth_destination` commented out (:71-72) — relay control rests on Postfix's implicit `smtpd_relay_restrictions` default.
- `conf/hs-master.cf` → host `/etc/postfix/master.cf` (update-install-host.sh:23). Adds `smtps` wrapper-mode listener restricted to `permit_sasl_authenticated,reject` (:7-12), amavis feed service `smtp-amavis` (:38-41) and re-injection listener `127.0.0.1:10025` (:42-55).
- `conf/ve-main.cf` → container `/etc/postfix/main.cf`; written by `write_ve_postfix_main` (postfixlib.sh:59) and **also directly by the containers module** at image build (containers/libs/mkrootfs_fedora.sh:72 and again :82). Key content: `compatibility_level = 3.8` (:5), `relayhost = srvctl-gateway` (:59), `home_mailbox = Maildir/` (:39), `mydestination = localhost, localhost.localdomain, $myhostname, $mydomain` (:67), TLS via `/etc/pki/tls/certs/postfix.pem` (:70-71), `message_size_limit = 26214400` (:56).
- `conf/ve-master.cf` — **installed by nothing** (no reference anywhere in *.sh/*.js); would enable the `submissions` (465) wrapper-mode service in containers (:32-47). Dead template; containers keep the stock Fedora master.cf.
- `conf/aliases` → host `/etc/aliases` via `make_aliases_db ''` (classic Fedora aliases file, everything → root; `root:` forward commented out at :96).

## State touched
- Host files: `/etc/postfix/{main.cf,master.cf,relaydomains,relaydomains.db,crt.pem,key.pem,ca-bundle.pem}`, `/etc/aliases` (+ `aliases.db` via postalias), `/etc/srvctl/system/{postfix,amavisd,spamassassin}.service` symlinks, `/etc/firewalld/services/` (if smtp/smtps xml needed), `/etc/srvctl/cert/*` read (via certificates helper).
- Container files: `/srv/<C>/rootfs/etc/postfix/main.cf` and timestamped `main.cf-$NOW.bak` backups; in the `mail` base image `$rootfs_base/etc/firewalld` zone config.
- systemd units: `postfix.service` (enable + restart, restarted again on every regenerate), `amavisd.service`, `spamassassin.service`, `firewalld.service` (started by firewalld helper).
- Datastore: reads `cluster postfix_relaydomains` and `container <name> exist` via `get` (node subprocess); writes nothing.
- Network: opens 25/tcp (`smtp`) and 465/tcp (`smtps`) in host firewalld default zone; same offline in mail-image; loopback 10024/10025 (amavis) and 8891 (opendkim milter) traffic implied.
- Packages installed: `spamassassin`, `postfix`, `amavisd-new` (dnf).

## Dependencies
- Core helpers: `msg`, `err`, `ntc` (lablib.sh), `run` (lablib.sh:93 — echoes and executes, warns via `eyif`), `exif` (kills command on hook failure, commonlib.sh:104), `$NOW` (init.sh:60, format `%Y.%m.%d-%H:%M:%S`), `$SC_INSTALL_DIR`, `$SC_LOG`.
- Modules: **containers** (activation source, calls `write_ve_postfix_conf` at add-ve, writes `ve-main.cf` itself at image build, drives `mkrootfs_fedora` hook); **datastore** (`get` bash wrapper + `cluster_postfix_relaydomains` in lib.js); **firewalld** (`firewalld_add_service`, `firewalld_offline_add_service`); **certificates** (`install_service_hostcertificate`); **srvctl** (`sc_install`, `add_service`, `msg_version_installed`; `update-install` and `regenerate`-calling commands drive the hooks); **branding** (`SC_COMPANY_DOMAIN`, defaults to `$HOSTNAME`); **opendkim** (expected to provide the 8891 milter referenced in hs-main.cf:82); **saslauthd** (provides cyrus SASL pwcheck for `smtpd_sasl_type = cyrus`); **perdition/dovecot** rely on the mail flow but are separate.
- External binaries: `postmap`, `postalias`, `postfix`, `systemctl`, `dnf`, `openssl` (dead diagnose), `firewall-cmd`/`firewall-offline-cmd` (via firewalld libs).

## Bugs & smells
- **medium** modules/postfix/conf/ve-master.cf:1 — template is referenced by no code in the repo, so containers keep the stock Fedora `master.cf` and the `submissions`/465 listener it defines (ve-master.cf:32-47) never exists; meanwhile hooks/mkrootfs_fedora.sh:5-6 opens `smtps` (465) in the mail image's firewalld. Concrete harm: mail containers advertise an open 465 port with nothing listening — SMTPS submission to mail containers silently cannot work.
- **medium** modules/postfix/diagnose.sh:1 — file sits at module root but hook dispatch only sources `hooks/<name>.sh` (commonlib.sh:97), so `sc diagnose` (modules/srvctl/commands/diagnose.sh:91) never runs it: postfix TLS/amavis diagnostics are silently missing. Additionally diagnose.sh:3 runs `openssl s_client` without `</dev/null`, so if the file were moved into `hooks/` as-is, `sc diagnose` would hang waiting for stdin.
- **medium** modules/postfix/libs/systemdlib.sh:17 — on restart failure the function ends with `systemctl status postfix.service --no-pager` (exit 3), so `restart_postfix` returns non-zero, and via hooks/regenerate.sh:5 + `exif` in run_hook (commonlib.sh:104) the *entire invoking command* exits. Concrete harm: a broken postfix aborts `add-ve`/`add-ve-user`/`add-codepad`/`regenerate` mid-flow — e.g. add-ve dies after the datastore entry and rootfs were created but before nspawn enable/start (containers/commands/add-ve.sh:38 runs the hook before the lib finishes container setup), leaving a half-built container.
- **low** modules/postfix/hooks/regenerate.sh:5 — unconditional full `systemctl restart` (not reload) of host postfix on every container/user add; drops in-flight SMTP connections cluster-wide each time an admin adds a VE, even when only relaydomains changed (postmap alone would suffice for map changes).
- **low** modules/postfix/hooks/version.sh:3 — dead hook; nothing calls `run_hook version` anywhere, and `sc version` hardcodes the identical `msg_version_installed postfix` (modules/srvctl/commands/version.sh:11). Dead/duplicated code only.
- **low** modules/postfix/libs/postfixlib.sh:67-90 — `write_postfix_main` has no callers, and its stated in-container use is unreachable because the module condition is always false inside nspawn containers (modules/containers/module-condition.sh:12-19). Dead code.
- **low** modules/postfix/hooks/update-install-host.sh:29 — `make_aliases_db ''` overwrites host `/etc/aliases` with the static template (libs/aliaseslib.sh:7) on every `sc update-install`; any locally-added alias (e.g. a `root:` forward for admin mail) is silently destroyed.
- **low** modules/postfix/conf/hs-main.cf:71-72 — `smtpd_recipient_restrictions` ends at `permit_sasl_authenticated` with `reject_unauth_destination` commented out; anti-relay depends solely on Postfix's implicit `smtpd_relay_restrictions` default, and `mynetworks` (hs-main.cf:20) whitelists all of `10.0.0.0/8` and `192.168.0.0/16` — any device on a shared private LAN segment can relay through the host. Deliberate for the VPN mesh, but fragile on hosts with other RFC1918 neighbors.

## Polish risks
Behaviors/outputs a rewrite must preserve byte-for-byte or semantically:
- Installed template contents: `conf/hs-main.cf` → `/etc/postfix/main.cf` (update-install-host.sh:14) plus the two appended lines — `"smtpd_tls_CAfile =    /etc/postfix/ca-bundle.pem"` with exactly four spaces (update-install-host.sh:18, only when the bundle exists) and `"smtpd_sasl_local_domain = $SC_COMPANY_DOMAIN"` (update-install-host.sh:21); `conf/hs-master.cf` → `/etc/postfix/master.cf` (:23); `conf/ve-main.cf` → container `main.cf` (postfixlib.sh:59; also containers/libs/mkrootfs_fedora.sh:72,82); `conf/aliases` → `/etc/aliases` (aliaseslib.sh:7).
- Semantics in ve-main.cf real installs depend on: `relayhost = srvctl-gateway` (ve-main.cf:59), `home_mailbox = Maildir/` (:39), `message_size_limit = 26214400` (:56); in hs-main.cf: relaydomains map path `hash:/etc/postfix/relaydomains` (:56), cert paths `/etc/postfix/crt.pem`/`key.pem` (:61-62), amavis ports 10024/10025 (hs-main.cf:79, hs-master.cf:42), milter port 8891 (hs-main.cf:82).
- Relaydomains file: path `/etc/postfix/relaydomains`, regenerated via `get cluster postfix_relaydomains` then `postmap` (postfixlib.sh:6-7); line format `<domain>\tOK` with `mail.` prefix stripped and aliases included (datastore/lib.js:941-951).
- The mail-pair convention: `write_ve_postfix_conf` writes main.cf for both `X` and `mail.X` based on the 5-char `"mail."` prefix test (postfixlib.sh:15-24); callers rely on it via containers addcontainerlib.sh:64.
- Backup naming: old container main.cf appended to `/srv/$C/rootfs/etc/postfix/main.cf-$NOW.bak` (postfixlib.sh:52) with `$NOW` = `%Y.%m.%d-%H:%M:%S` (init.sh:60).
- firewalld service names exactly `smtp` and `smtps` on host (hooks/firewalld.sh:3-4) and in the `mail` image only (hooks/mkrootfs_fedora.sh:3-7, keyed on `$rootfs_name == "mail"`).
- systemd interactions: `add_service postfix|amavisd|spamassassin` (enable + restart + status + `/etc/srvctl/system/` symlink, update-install-host.sh:25-27); `systemctl restart postfix.service` (systemdlib.sh:5) — restart, not reload.
- User-visible strings (grep-able by operators/scripts): `"Installing postfix."` (update-install-host.sh:5), `"Writing postfix configuration for $container"` (postfixlib.sh:44), `"$conf does not exist"` (postfixlib.sh:50), `"$container dont exists"` including the typo (postfixlib.sh:62), `"write postfix for mail container"` / `"write postfix for container"` (postfixlib.sh:17,21), `"restarted postfix.service"` (systemdlib.sh:11), `"Postfix restart FAILED!"` (systemdlib.sh:16).
- Error/exit semantics: `write_ve_postfix_main` returns 0 silently when `/srv/$container` or its `etc/postfix` is missing (postfixlib.sh:32-40); hook failures propagate through run_hook's `exif` and abort the whole command with the hook's exit code (commonlib.sh:104).
- Package set: `spamassassin postfix amavisd-new` (update-install-host.sh:7-9).

## v4 notes
- Three copies of "install ve-main.cf into a rootfs" exist: postfixlib.sh:59, postfixlib.sh:86 (dead), containers/libs/mkrootfs_fedora.sh:72 and :82 (written twice in the same function). One templated `installVeMainCf(rootfs)` in .mjs, called by both the image builder and add-ve, removes all drift risk. (Also observed while auditing, belongs to the containers sheet: containers/libs/mkrootfs_fedora.sh:69 `mkdir -p "$rootfs_base"/rootfs/etc/postfix` creates a stray `/rootfs/etc/postfix` dir inside the image — path typo.)
- The relaydomains pipeline (datastore lib.js:935-958 → bash `get` → `postmap`) is a natural .mjs unit: generate + write + postmap + `postfix reload` in one function, with reload instead of restart when only maps changed.
- Hook discovery in v4 should either auto-register `diagnose`/`version` per module or drop the pattern; two of this module's five hook-ish files are dead today (diagnose.sh misplaced, version.sh never invoked).
- Decide the container-465 story: either wire `ve-master.cf` in (and keep the mail-image firewall opening) or delete both; today they are inconsistent halves.
- main.cf generation by `cat template` + `echo >>` appends (update-install-host.sh:14-23) works but is fragile; v4 should render from a single template with variables (`SC_COMPANY_DOMAIN`, CA bundle presence) — postconf(1) or a template engine — keeping output identical.
- `restart_postfix` should distinguish "config changed → reload" from "install → restart", and a mail-service failure should degrade to a warning during container-creation flows rather than aborting them mid-way.
- `conf/aliases` is a legacy Fedora aliases snapshot; v4 could ship only a drop-in delta or keep the distro file and manage just the `root:` forward, avoiding the clobber-on-update-install behavior.
- The `mail.` prefix pairing convention (postfixlib.sh:15-24, datastore lib.js:941-942) is implicit shared knowledge between two modules; v4 should centralize it in one exported helper (e.g. datastore model) so postfix, dns, and haproxy agree on it.
