# 021 — FIXME(v4) inventory (reconciled, generated 2026-07-05)

Complete machine-generated list of every `## FIXME(v4):` marker in
non-vendored source on branch v4. Regenerate with
scratchpad/inv.mjs (grep FIXME(v4), exclude vncproxy/waf + vncproxy/vncproxy).

**Total markers: 427** across 38 units.

This inventory is the reconciliation Codex's audit-the-audit asked for:
every marker here is a Stage-2 candidate. 003-discovery-findings.md holds
the discovery-time findings (301); this list is the in-tree superset
(discovery findings that became markers + new defects found during
polishing, e.g. the networkd exit-0 and ssh 'run > unit' items). When
100-series work packages are cut, draw from THIS list, not 003 alone.

| unit | count |
|------|------|
| backup | 16 |
| backupdb | 5 |
| branding | 3 |
| ca | 11 |
| certificates | 11 |
| codepad | 12 |
| containers | 45 |
| core | 5 |
| datastore | 11 |
| default | 7 |
| dns | 7 |
| firewalld | 6 |
| ftp | 3 |
| gluster | 8 |
| gui | 16 |
| haproxy | 12 |
| letsencrypt | 12 |
| mariadb | 12 |
| mozilla | 7 |
| named | 15 |
| nfs | 10 |
| ntp | 3 |
| odoo | 12 |
| opendkim | 8 |
| openvpn | 14 |
| password | 4 |
| perdition | 13 |
| postfix | 7 |
| saslauthd | 9 |
| srvctl | 22 |
| ssh | 15 |
| sshpiperd | 11 |
| static | 11 |
| usersonhost | 19 |
| usersonve | 14 |
| ve | 6 |
| vncproxy | 12 |
| wordpress | 13 |

---

## backup (16)

- `modules/backup/libs/7zlib.sh:27` — non-SC_-prefixed config var: the rsync backups (sclib.sh) key off
- `modules/backup/libs/7zlib.sh:47` — bare "exit" (deliberate disable, e179f53) terminates the whole
- `modules/backup/libs/7zlib.sh:57` — probe compares ssh output to the short name $C; containers whose
- `modules/backup/libs/7zlib.sh:68` — redirecting "run" captures its colored command-echo line
- `modules/backup/libs/sclib.sh:51` — unquoted expansion word-splits and glob-expands: directory
- `modules/backup/libs/sclib.sh:68` — substring match over the whole systemctl status tree: any
- `modules/backup/libs/sclib.sh:79` — geometry is TTY-only, so under cron the size/count vars stay
- `modules/backup/libs/sclib.sh:151` — unquoted expansion word-splits and glob-expands: directory
- `modules/backup/libs/sclib.sh:168` — substring match over the whole systemctl status tree: any
- `modules/backup/libs/sclib.sh:179` — geometry is TTY-only, so under cron the size/count vars stay
- `modules/backup/libs/sclib.sh:221` — mislabeled "local-backup-failure" (copy-paste from
- `modules/backup/libs/sclib.sh:259` — unquoted expansion word-splits and glob-expands: directory
- `modules/backup/libs/sclib.sh:276` — substring match over the whole systemctl status tree: any
- `modules/backup/libs/sclib.sh:287` — geometry is TTY-only, so under cron the size/count vars stay
- `modules/backup/libs/sclib.sh:320` — reachability was probed above as plain $host but the transfer
- `modules/backup/libs/sclib.sh:333` — mislabeled "local-backup-failure" (copy-paste from

## backupdb (5)

- `modules/backupdb/libs/backupdblib.sh:36` — detection keys only on /var/lib/mongodb (Fedora datadir); mongodb.org RPM installs use /var/lib/mongo and are silently never backed up
- `modules/backupdb/libs/backupdblib.sh:51` — the previous dump is deleted before the new one is attempted; if mongodump fails, zero backups remain
- `modules/backupdb/libs/backupdblib.sh:56` — vendored mongo-tools r3.6.0 (2017, x86_64-only) is used even when a current /usr/bin/mongodump exists; incompatible with mongod 4.2+
- `modules/backupdb/libs/backupdblib.sh:57` — mongodump exit status is never checked (no exif/eyif); a failed or partial dump is indistinguishable from success
- `modules/backupdb/module-condition.sh:10` — unconditionally true - the module and its lib load on every machine, even ones with no databases

## branding (3)

- `modules/branding/hooks/post-init.sh:11` — note in hooks/pre-init.sh.
- `modules/branding/hooks/pre-init.sh:19` — SC_RESELLER_USER is defaulted here but never exported
- `modules/branding/libs/brandinglib.sh:28` — the double quotes around the logo substitution and the

## ca (11)

- `modules/ca/libs/calib.sh:44` — no expiry check on the root CA cert (unlike leaf certs
- `modules/ca/libs/calib.sh:75` — $1 is not validated — certificates/hooks/update-install-host.sh
- `modules/ca/libs/calib.sh:91` — chmod -R 600 strips the execute bit from every directory
- `modules/ca/libs/calib.sh:99` — hardcodes /etc/srvctl/CA instead of $SC_ROOTCA_DIR — with
- `modules/ca/libs/calib.sh:137` — depends on the certificates module's tree — the
- `modules/ca/libs/calib.sh:195` — a correct-quoting rewrite of run would break this call
- `modules/ca/libs/calib.sh:210` — stale bundle — the .p12 is only created when missing, so
- `modules/ca/libs/netlib.sh:12` — design-level security issue — ca_sync replicates the ENTIRE CA
- `modules/ca/libs/netlib.sh:26` — short-name vs FQDN mismatch makes this comparison
- `modules/ca/libs/netlib.sh:32` — path hardcodes /etc/srvctl/CA — a customized
- `modules/ca/module-condition.sh:13` — the /etc/openvpn check runs before any container guard, so the

## certificates (11)

- `modules/certificates/hooks/update-install-host.sh:49` — root_CA_init is called with no argument, creating a nameless
- `modules/certificates/hooks/update-install-host.sh:55` — install_acme also runs from the letsencrypt module's own
- `modules/certificates/libs/domaincertlib.sh:25` — returns 0 unconditionally, so the caller's 'if check_pem' is
- `modules/certificates/libs/domaincertlib.sh:132` — "$ssl_pem $ssl_pem" only works because run
- `modules/certificates/libs/domaincertlib.sh:184` — the passphrase is persisted in config.txt (output_password)
- `modules/certificates/libs/domaincertlib.sh:245` — both combined pems contain the private key but are created
- `modules/certificates/libs/servicecertlib.sh:118` — 1024-bit DH parameters are Logjam-weak and rejected
- `modules/certificates/libs/servicecertlib.sh:135` — bare 'exit' exits with the status of err (0), so this
- `modules/certificates/libs/wildcardcertlib.sh:76` — $SC_DATASTORE_DIR/cert is never created by
- `modules/certificates/libs/wildcardcertlib.sh:80` — the copy contains the private key but is
- `modules/certificates/libs/wildcardcertlib.sh:86` — self-contradictory condition — whenever

## codepad (12)

- `modules/codepad/access.js:24` — much of the scaffolding below (CMD, SC_UID0, hosts, resellers,
- `modules/codepad/access.js:108` — side effect — creates empty datastore user directories for
- `modules/codepad/access.js:135` — high — this copies the user's PLAINTEXT .password file
- `modules/codepad/commands/add-codepad.sh:46` — duplicate — init_codepad_project already runs this hook;
- `modules/codepad/libs/create_codepad_certificate.sh:18` — the ssl_* variables below leak into the global shell
- `modules/codepad/libs/create_codepad_certificate.sh:32` — appending — after a partial previous run (key present, crt
- `modules/codepad/libs/mkrootfs_fedora_install_codepad.sh:45` — host-absolute path inside the chroot (doubles to
- `modules/codepad/libs/mkrootfs_fedora_install_codepad.sh:50` — single quotes without -e write a literal \n into project.log
- `modules/codepad/libs/mkrootfs_fedora_install_codepad.sh:54` — dangling symlink — no mongodb package is in the install
- `modules/codepad/libs/mkrootfs_fedora_install_codepad.sh:63` — changes the srvctl process CWD and never restores it;
- `modules/codepad/libs/mkrootfs_fedora_install_codepad.sh:67` — bakes the host template path as the clone's origin URL
- `modules/codepad/libs/mkrootfs_fedora_install_codepad.sh:72` — $CDN is defined nowhere in the repo or example-conf

## containers (45)

- `modules/containers/command.sh:10` — the 'show' spec below carries the action 'poweroff VE' — a GUI
- `modules/containers/command.sh:45` — a bare 'sc restart' (no service resolved upstream) lands here
- `modules/containers/command.sh:113` — everything from here to the end of this branch is
- `modules/containers/commands/add-network-ve.sh:29` — bare exit returns 0 — the missing-bridge failure reports success.
- `modules/containers/commands/add-ve-user.sh:28` — unanchored regex — =~ matches a substring, so any name
- `modules/containers/commands/add-ve.sh:46` — sourcing the template os-release into the running shell
- `modules/containers/commands/destroy-ve.sh:54` — broken root gate — SC_UID0 is always the string 'true' or
- `modules/containers/commands/destroy-ve.sh:102` — unbounded loop — a busy or stale mount inside /srv/$C
- `modules/containers/commands/destroy-ve.sh:121` — bare exit returns 0 — the access-denied path reports success.
- `modules/containers/commands/map-port.sh:43` — silent bare exit (status 0) — a non-owner gets no error
- `modules/containers/commands/recreate-ve.sh:67` — HIGH — tmp_rootfs is never deleted after a successful run,
- `modules/containers/commands/recreate-ve.sh:141` — missing leading / — this relative path deletes
- `modules/containers/commands/remove-ve.sh:17` — the multi-line help above still describes the old 7z
- `modules/containers/commands/remove-ve.sh:20` — 90% duplicate of destroy-ve.sh — collapse in v4.
- `modules/containers/commands/remove-ve.sh:49` — broken root gate — SC_UID0 is always the string 'true' or
- `modules/containers/commands/remove-ve.sh:98` — unbounded loop — a busy or stale mount inside /srv/$C
- `modules/containers/commands/remove-ve.sh:115` — bare exit returns 0 — the access-denied path reports success.
- `modules/containers/commands/update-ve.sh:21` — stops the container's unit and then only prints
- `modules/containers/hooks/adjust-service.sh:27` — tautological ownership test — the trailing
- `modules/containers/hooks/update-install-host.sh:36` — 'chown 750' uses a mode as owner — the directory ends up
- `modules/containers/libs/addcontainerlib.sh:72` — 'run cat X > Y' redirects run's ANSI banner into the
- `modules/containers/libs/all_containers_quota_check.sh:13` — dead — nothing reads SIZE_LIMIT; it duplicates the
- `modules/containers/libs/all_containers_quota_check.sh:39` — if the quota lookup fails, quota is empty and the
- `modules/containers/libs/allcontainerslib.sh:64` — hard-coded reference targets — the message even claims
- `modules/containers/libs/authlib.sh:14` — SC_ON_HS is never assigned anywhere in bash — with the
- `modules/containers/libs/backupcontainerlib.sh:21` — broken root gate — SC_UID0 is the string 'true'/'false',
- `modules/containers/libs/backupcontainerlib.sh:35` — 'run' performs no redirection — '>' and the path
- `modules/containers/libs/backupcontainerlib.sh:48` — HIGH — 'run' does not eval, so the remote shell
- `modules/containers/libs/backupcontainerlib.sh:65` — bare exit returns 0 — the (dead) deny path would
- `modules/containers/libs/create-container.sh:51` — with an empty type (unknown /srv dir reconciled by
- `modules/containers/libs/mkrootfs_arch.sh:52` — copy-paste — arch images run the DEBIAN hook set and
- `modules/containers/libs/mkrootfs_fedora.sh:73` — typo'd path creates a junk rootfs/etc/postfix directory
- `modules/containers/libs/mkrootfs_ubuntu.sh:48` — runs the debian hook set (copy-paste?) — possibly meant
- `modules/containers/libs/mkrootfslib.sh:38` — dead code — no callers anywhere; delete or wire up.
- `modules/containers/libs/nspawnlib.sh:7` — dead code — update_nspawn_container has no callers and is
- `modules/containers/libs/regenlib.sh:108` — runs for ANY /srv entry without rootfs/ (only
- `modules/containers/libs/regenlib.sh:151` — '[[ $(get ...) ]]' is true for BOTH 'true' and
- `modules/containers/libs/statuslib.sh:22` — HIGH — any op other than 'start' falls through to
- `modules/containers/libs/statuslib.sh:122` — undefined function — the definition above is named
- `modules/containers/libs/systemlib.sh:14` — dead code — create_userslice_config has no callers; its
- `modules/containers/libs/systemlib.sh:129` — dead code — no callers; would only re-run every container's
- `modules/containers/libs/systemlib.sh:162` — idempotence check tests /usr/lib/... but the unit is
- `modules/containers/status.js:18` — per-container failures are not isolated — a deleted user
- `modules/containers/status.js:25` — monkey-patching Object.prototype.length (and
- `modules/containers/status.js:174` — throws when the container's user is missing from users.json

## core (5)

- `commonlib.sh:136` — operator precedence — && binds tighter than ||, so the
- `commonlib.sh:244` — a '## &&&' line ANYWHERE in a command file (heredocs
- `commonlib.sh:375` — unlike hint_commands, this full listing skips the
- `init.sh:28` — for a non-root user on a box missing these symlinks, every
- `lablib.sh:123` — this warning can never print — eyif is called from the

## datastore (11)

- `modules/datastore/apps/datastore-server.js:47` — path traversal — req.url is appended unsanitized, so a
- `modules/datastore/lib.js:41` — dead readonly guard — SC_DATASTORE_RO is never exported anywhere
- `modules/datastore/lib.js:53` — SC_USER, NOW and ON_HS are implicit globals (no var/const/let);
- `modules/datastore/lib.js:295` — dead code — container_user is not exported and has no callers
- `modules/datastore/lib.js:480` — when no port argument is given, port_arg stays undefined and
- `modules/datastore/lib.js:871` — stray debug output on every container creation (captured
- `modules/datastore/libs/bashlib.sh:111` — __result is declared but never assigned (node output goes
- `modules/datastore/libs/bashlib.sh:126` — same as del — __result is never assigned, so the exif text
- `modules/datastore/main.js:53` — SC_HOSTS_DATA_FILE, SC_USERS_DATA_FILE, SC_CONTAINERS_DATA_FILE,
- `modules/datastore/main.js:63` — SC_USER is an implicit global (no var/const/let declaration);
- `modules/datastore/main.js:183` — duplicate ADD blocks — for `add container X vncuser Y`

## default (7)

- `modules/default/hooks/update-install-host.sh:19` — Restart=always with no RestartSec — if server.js crashes at
- `modules/default/hooks/update-install-host.sh:22` — nothing ever stops, disables or removes this unit when the
- `modules/default/hooks/update-install-host.sh:42` — failures of enable/start are silently swallowed — 'run'
- `modules/default/hooks/update-install-host.sh:46` — 'start' (not 'restart') — after a srvctl code update an
- `modules/default/server.js:18` — unguarded readFileSync — if /var/www/html/404.html is absent
- `modules/default/server.js:22` — html404 is an implicit global (no var/let/const); works only
- `modules/default/server.js:37` — listen(1282) binds all interfaces although the only

## dns (7)

- `modules/dns/dns-scan.js:26` — much of the scaffolding below (CMD, SRVCTL, SC_UID0,
- `modules/dns/dns-scan.js:89` — low — resolver hardcoded to the single upstream 8.8.8.8,
- `modules/dns/dns-scan.js:123` — medium — records are reset to [] before the hourly-skip
- `modules/dns/dns-scan.js:157` — medium — AAAA/MX/NS lookups run only inside the
- `modules/dns/dns-scan.js:191` — medium — unconditional writeFileSync of the entire stale
- `modules/dns/hooks/regenerate.sh:16` — medium — the scan runs synchronously inside every regenerate
- `modules/dns/hooks/update-install-host.sh:14` — high — this writes "DNS=8.8.8.8" with no [Resolve] section

## firewalld (6)

- `modules/firewalld/hooks/diagnose.sh:15` — $zone leaks in from the parent diagnose command, which sets
- `modules/firewalld/hooks/firewalld.sh:18` — mail ports and elasticsearch 9200 are opened on every
- `modules/firewalld/hooks/mkrootfs_fedora.sh:30` — baked into every fedora template regardless of role — a
- `modules/firewalld/hooks/update-install-ve.sh:12` — unconditional sc_install, but sc_install is only defined on
- `modules/firewalld/libs/firewalldlib.sh:23` — hidden side effect — every call from any module starts
- `modules/firewalld/libs/firewalldlib.sh:54` — for an unknown service name with empty proto/port this

## ftp (3)

- `modules/ftp/hooks/firewalld.sh:12` — plaintext-FTP port 21 is opened permanently on every
- `modules/ftp/hooks/update-install-host.sh:12` — vsftpd is installed but never configured, enabled or started —
- `modules/ftp/hooks/update-install-host.sh:15` — a transient dnf/repo failure here aborts the entire

## gluster (8)

- `modules/gluster/hooks/update-install-host.sh:50` — the reachability probe disables host-key verification (so it
- `modules/gluster/libs/glustercertlib.sh:12` — drop this file — it duplicates hooks/update-install-host.sh
- `modules/gluster/libs/glusterlib.sh:31` — stale hardcoded path — the real mountpoint is
- `modules/gluster/libs/glusterlib.sh:39` — operates on the caller's current working directory, not the
- `modules/gluster/libs/glusterlib.sh:84` — "return 0" on an inactive glusterd — the datastore and
- `modules/gluster/libs/glusterlib.sh:180` — the four error paths below end with err + bare "return";
- `modules/gluster/libs/glusterlib.sh:209` — matches the exact column spacing of "gluster volume status"
- `modules/gluster/module-condition.sh:52` — deliberate kill-switch — the success branch echoes false

## gui (16)

- `modules/gui/hooks/update-install-host.sh:12` — high - hook disabled with "if false" for the whole v3 line: the
- `modules/gui/libs/spec.sh:26` — hint grep lacks -m 1: two hint lines in a file head embed a
- `modules/gui/libs/spec.sh:29` — the file operand makes grep ignore the head pipe, so a
- `modules/gui/libs/spec.sh:55` — iterates all modules regardless of enablement (unlike the
- `modules/gui/make_node_modules.sh:8` — low - uses the srvctl helper `run` but is never sourced under
- `modules/gui/server.js:17` — strict mode disabled; e.g. the spec parser's loop index i is
- `modules/gui/server.js:28` — SC_DATASTORE_DIR and SC_INSTALL_DIR hardcoded; a non-standard
- `modules/gui/server.js:69` — dead mount - nothing installs the wetty npm package, and
- `modules/gui/server.js:79` — datastore JSONs (and commands.spec below) are read once at
- `modules/gui/server.js:132` — the spec includes every user's ~/srvctl-includes commands,
- `modules/gui/server.js:160` — host/container are client-supplied and there is no check
- `modules/gui/server.js:177` — throw inside an async callback - any exec-channel
- `modules/gui/server.js:206` — 500 ms connect timeout is routinely exceeded on hosts
- `modules/gui/server.js:231` — no guard on the Referer header - a socket.io client
- `modules/gui/server.js:296` — only text captured inside SGR color sequences is HTML-escaped;
- `modules/gui/srvctl-gui/scripts.js:2` — dead file - referenced by no page (index.html and

## haproxy (12)

- `modules/haproxy/commands/http-redirect.sh:46` — broken root gate — SC_UID0 is always the string 'true' or
- `modules/haproxy/commands/http-redirect.sh:59` — bare exit returns 0 — the access-denied path reports success.
- `modules/haproxy/commands/https-redirect.sh:45` — inconsistent root gate — twin http-redirect.sh tests the
- `modules/haproxy/commands/https-redirect.sh:56` — bare exit returns 0 — the access-denied path reports success.
- `modules/haproxy/haproxy.js:29` — unused imports/vars kept verbatim for the byte-identical
- `modules/haproxy/haproxy.js:124` — no guard — with SC_COMPANY_DOMAIN unset this yields '<name>.undefined'
- `modules/haproxy/haproxy.js:301` — 'j' is an undeclared implicit global here and in every
- `modules/haproxy/hooks/diagnose.sh:9` — resurrect as real 'show stat' diagnostics or drop the hook.
- `modules/haproxy/libs/proxylib.sh:17` — check_pem deletes admin-managed SOURCE certificates up to 7
- `modules/haproxy/libs/proxylib.sh:49` — SC_DATASTORE_DIR may resolve to the read-only gluster dir,
- `modules/haproxy/libs/proxylib.sh:60` — hardcoded path — should honor SC_DATASTORE_RW_DIR.
- `modules/haproxy/libs/systemdlib.sh:37` — no else branch — if the reload fails while the old

## letsencrypt (12)

- `modules/letsencrypt/apps/acme-server.js:32` — fs.R_OK is a long-deprecated alias of fs.constants.R_OK;
- `modules/letsencrypt/letsencrypt.js:57` — SC_CONTAINERS_DATA_FILE, SC_UID0 and localhost below are
- `modules/letsencrypt/letsencrypt.js:75` — return_value, return_error and output are copy-pasted helper
- `modules/letsencrypt/letsencrypt.js:121` — users, resellers, user and container below are never used
- `modules/letsencrypt/letsencrypt.js:172` — prints the raw openssl command via ntc on every call (constant
- `modules/letsencrypt/letsencrypt.js:222` — per-domain deploy failures are invisible to the caller
- `modules/letsencrypt/letsencrypt.js:228` — cert_pem below is declared but never used (dead symbol).
- `modules/letsencrypt/letsencrypt.js:232` — /etc/letsencrypt/ca.pem is the vendored letsencrypt-ca.pem
- `modules/letsencrypt/letsencrypt.js:286` — asymmetric log filenames — the non-www run appends to
- `modules/letsencrypt/letsencrypt.js:371` — operator precedence bug in the nameserver hint — '+'
- `modules/letsencrypt/libs/letsencryptlib.sh:43` — useradd is unguarded — on re-install it prints
- `modules/letsencrypt/libs/letsencryptlib.sh:70` — the vendored letsencrypt-ca.pem is DST Root CA X3,

## mariadb (12)

- `modules/mariadb/hooks/init.sh:14` — low — redundant: libs/mariadblib.sh defaults
- `modules/mariadb/libs/mariadblib.sh:67` — high — bare 'exit' exits with the status of err, which
- `modules/mariadb/libs/mariadblib.sh:85` — medium — the previous dump generation is destroyed before
- `modules/mariadb/libs/mariadblib.sh:98` — low — 'grep -v Database' strips the header line but also
- `modules/mariadb/libs/mariadblib.sh:108` — low — exif without a message prints an empty error
- `modules/mariadb/libs/mariadblib.sh:144` — medium — 15-char user truncation: two sites whose
- `modules/mariadb/libs/mariadblib.sh:161` — low — SQL assembled by string interpolation; names not
- `modules/mariadb/libs/mariadblib.sh:177` — medium — credential file is created with the default umask
- `modules/mariadb/libs/mariadblib.sh:207` — medium — on MariaDB >= 10.4 (Fedora ships 10.5+)
- `modules/mariadb/libs/mariadblib.sh:224` — low — root DB password logged in plaintext to SC_LOG
- `modules/mariadb/libs/mariadblib.sh:228` — medium — conf file created with the default umask
- `modules/mariadb/module-condition.sh:17` — low — the ve fallthrough enables this module in every

## mozilla (7)

- `modules/mozilla/apps/mozilla-autoconfig-server.js:17` — smell — os.hostname() is captured once at startup; a
- `modules/mozilla/apps/mozilla-autoconfig-server.js:31` — low — provider id is hardcoded to D250.hu on every
- `modules/mozilla/apps/mozilla-autoconfig-server.js:65` — low — every method and path gets 200 + the full config XML;
- `modules/mozilla/apps/mozilla-autoconfig-server.js:77` — medium — no bind address, so this root-owned process listens
- `modules/mozilla/libs/install.sh:22` — low — Description says "Letsencrypt server.", copy-pasted
- `modules/mozilla/libs/install.sh:24` — medium — runs as root and the app binds 0.0.0.0:1029,
- `modules/mozilla/libs/install.sh:50` — low — this status check is the function's (and the sourced

## named (15)

- `modules/named/commands/override-in-address.sh:41` — high — SC_UID0 is always the literal string 'true' or 'false'
- `modules/named/commands/override-in-address.sh:50` — low — despite the help text, the named zone file is not
- `modules/named/installnamedlib.sh:15` — medium (dormant) — ExecStart points at
- `modules/named/installnamedlib.sh:48` — high (latent) — the hard-coded include of /var/named/d250.conf
- `modules/named/installnamedlib.sh:54` — medium — bindkeys-file "/etc/named.iscdlv.key" is an obsolete
- `modules/named/libs/install.sh:28` — medium — ntp/ntpd is retired on current Fedora (chrony
- `modules/named/libs/install.sh:48` — medium — recent bind packages no longer ship
- `modules/named/libs/install.sh:77` — low (dormant) — $CDN is never defined in any bash scope
- `modules/named/libs/install.sh:102` — low (dormant) — dnssec-keygen -a HMAC-MD5 is
- `modules/named/libs/install.sh:108` — low (dormant) — /var/dyndns/srvctl.private is never
- `modules/named/named.js:127` — low — 'r = br' creates an implicit global (no var); works only
- `modules/named/named.js:276` — low — for a use_gsuite domain missing its google
- `modules/named/named.js:350` — medium — no effective timeout: the https.Agent timeout only
- `modules/named/named.js:408` — the local host is fetched over HTTPS too, although get_conf
- `modules/named/named.js:419` — medium — this exit handler also runs after return_error's

## nfs (10)

- `modules/nfs/hooks/diagnose.sh:15` — low — pings $host by DNS name (public route) while actual NFS
- `modules/nfs/hooks/diagnose.sh:24` — low — no timeout here (unlike the probes in
- `modules/nfs/hooks/regenerate.sh:11` — smell — never re-generates /etc/exports (only update-install
- `modules/nfs/hooks/update-install-host.sh:14` — medium — "Install NFS" never installs the nfs-utils package;
- `modules/nfs/hooks/update-install-host.sh:26` — low — nfs_mount runs before rpcbind/nfs-server are enabled
- `modules/nfs/libs/nfslib.sh:27` — low — clobbers the whole /etc/exports, silently destroying any
- `modules/nfs/libs/nfslib.sh:29` — security — /srv is exported rw,no_root_squash to the entire
- `modules/nfs/libs/nfslib.sh:52` — medium — no "$host == $HOSTNAME" skip, so each host
- `modules/nfs/libs/nfslib.sh:70` — medium — no already-mounted check; every
- `modules/nfs/libs/nfslib.sh:76` — smell — misleading text: the step that failed

## ntp (3)

- `modules/ntp/hooks/update-install-host.sh:14` — no idempotence guard — every update-install re-runs dnf
- `modules/ntp/hooks/update-install-host.sh:18` — chronyd (Fedora's default time daemon) is never disabled;
- `modules/ntp/hooks/update-install-host.sh:21` — if this start (or the install above) fails, the hook's

## odoo (12)

- `modules/odoo/commands/install-odoo.sh:134` — redundant re-check of the srvctl permission gate at the top; exits 1 (not srvctl's auth code 44) and misfires when USER is unset (cron/systemd context…
- `modules/odoo/commands/install-odoo.sh:142` — dead code — tempfiles is never populated, so cleanup removes nothing; the EXIT trap also leaks into the persistent srvctl shell because this file is s…
- `modules/odoo/commands/install-odoo.sh:164` — inert — this file is sourced inside an 'if run_command' condition, where bash ignores errexit; every failing step (dnf, initdb, git, pip) falls throug…
- `modules/odoo/commands/install-odoo.sh:172` — hardcoded Croatian locale from the upstream author's environment; glibc-langpack-hr is never installed, so on minimal Fedora images initdb fails with …
- `modules/odoo/commands/install-odoo.sh:182` — unconditional full package upgrade of the production container as a hidden side effect of an install command
- `modules/odoo/commands/install-odoo.sh:184` — package name 'node' does not exist in Fedora (the binary comes from 'nodejs'); dnf aborts the whole transaction so none of these dependencies get inst…
- `modules/odoo/commands/install-odoo.sh:214` — guard only checks that initdb ran; if the role/template setup below fails (or postgres was preinstalled), a re-run skips this block forever and the od…
- `modules/odoo/commands/install-odoo.sh:236` — OCB 14.0 is EOL (2023); its requirements.txt pins no longer build against current Fedora Python, so the venv install below fails on current images
- `modules/odoo/commands/install-odoo.sh:251` — chowns everything under the container's /srv to odoo, not just the trees created here — silently takes over any co-hosted application data (also below…
- `modules/odoo/commands/install-odoo.sh:317` — the $1 below expands to the sourcing dispatcher's first positional parameter (always empty today) — a leftover dry-run mechanism from the standalone i…
- `modules/odoo/commands/install-odoo.sh:346` — deletes hard-coded line 218 assuming it is the vhost closing tag of the stock mod_ssl file; any packaging shift or prior edit removes the wrong line a…
- `modules/odoo/commands/install-odoo.sh:399` — the ERR trap is installed only here, after all work is done, so it never guards any step above — and it leaks into the persistent srvctl shell (source…

## opendkim (8)

- `modules/opendkim/hooks/update-install-host.sh:58` — low — regenerate_opendkim above is commented out, but
- `modules/opendkim/hooks/version.sh:14` — low — dead hook, never executed; either wire a version
- `modules/opendkim/libs/opendkimlib.sh:41` — low — unquoted glob: when no per-domain key
- `modules/opendkim/opendkim.js:29` — most of the shared datastore-js boilerplate below is dead
- `modules/opendkim/opendkim.js:119` — low — the domain name is interpolated unescaped into a
- `modules/opendkim/opendkim.js:142` — medium — txt.split('"')[3] assumes opendkim-genkey
- `modules/opendkim/opendkim.js:158` — low — table lines are appended even when the key is not
- `modules/opendkim/opendkim.js:182` — medium — containers.json is rewritten wholesale from the

## openvpn (14)

- `modules/openvpn/hooks/adjust-service.sh:32` — low — glob without nullglob: with no matching conf the
- `modules/openvpn/hooks/pre-init.sh:11` — smell — SC_OPENVPN_HOSTNET_SERVER is defaulted on every
- `modules/openvpn/hooks/update-install-host.sh:52` — low — if the glob has no match (e.g. the grab above failed
- `modules/openvpn/hooks/update-install-host.sh:82` — medium — ln -s without -f is not idempotent: on every
- `modules/openvpn/hooks/update-install-host.sh:108` — medium — when write_openvpn_client_config bails out
- `modules/openvpn/hooks/update-install-host.sh:123` — medium — same ln -s idempotency noise as the server
- `modules/openvpn/hooks/update-install-host.sh:127` — high — unit name typo "cleint": every client tunnel is
- `modules/openvpn/hooks/update-install-host.sh:136` — medium — dead repair attempt: -f on the hostnet-ccd
- `modules/openvpn/libs/openvpn_install.sh:13` — drop this file — dead code; the whole module is a deprecation
- `modules/openvpn/libs/openvpnconfiglib.sh:30` — high — this line re-writes the fedora-27 path instead of
- `modules/openvpn/libs/openvpnconfiglib.sh:76` — the usernet TODO (tcp 1100) has been pending since v3 —
- `modules/openvpn/libs/openvpnlib.sh:99` — medium — all three blocks below fetch only when the
- `modules/openvpn/libs/openvpnlib.sh:111` — smell — message hardcodes "usernet" even when
- `modules/openvpn/module-condition.sh:20` — the /etc/openvpn check runs before any container guard, so the

## password (4)

- `modules/password/lib.js:9` — Math.random() is not cryptographically secure and pattern
- `modules/password/libs/bashlib.sh:13` — 2>&1 merges node stderr into the captured value; a
- `modules/password/libs/bashlib.sh:18` — "SSH-ERROR" is copy-pasted from an SSH lib; a node
- `modules/password/libs/get-password.sh:26` — $RANDOM is not cryptographically secure and the pattern

## perdition (13)

- `modules/perdition/hooks/firewalld.sh:15` — low — dead branch: the only path into this hook is the
- `modules/perdition/hooks/regenerate.sh:18` — high — on a fresh host the perdition installer never runs
- `modules/perdition/hooks/update-install-host.sh:13` — high — install_perdition has no caller anywhere, so a
- `modules/perdition/hooks/version.sh:14` — low — dead hook, never executed; either wire a version
- `modules/perdition/libs/install_perdition.sh:38` — low — this /etc/perdition/popmap.re seed is never
- `modules/perdition/libs/install_perdition.sh:51` — low — removes RPM-owned unit files; any perdition
- `modules/perdition/perdition.js:18` — most of this file is copy-pasted datastore-module
- `modules/perdition/perdition.js:25` — low — ntc, get, run, rok, err are imported but unused.
- `modules/perdition/perdition.js:32` — low — out() is dead code, never called.
- `modules/perdition/perdition.js:41` — low — CMD, SRVCTL, SC_UID0, HOSTNAME, localhost are
- `modules/perdition/perdition.js:59` — low — return_value() and output() are dead code, never
- `modules/perdition/perdition.js:81` — low — hosts, users, resellers, user, container are unused;
- `modules/perdition/perdition.js:106` — low — dom is interpolated into the regex

## postfix (7)

- `modules/postfix/diagnose.sh:12` — medium — misplaced hook, 'sc diagnose' never runs it; note
- `modules/postfix/hooks/mkrootfs_fedora.sh:13` — medium — smtps (465) is opened here, but conf/ve-master.cf
- `modules/postfix/hooks/regenerate.sh:13` — low — full restart (not reload) on every regenerate drops
- `modules/postfix/hooks/update-install-host.sh:41` — low — rewrites host /etc/aliases from the static template
- `modules/postfix/hooks/version.sh:12` — low — dead hook, never executed; either wire a version hook
- `modules/postfix/libs/postfixlib.sh:92` — low — dead code, no callers anywhere in the tree, and the
- `modules/postfix/libs/systemdlib.sh:28` — medium — on failure the function ends with this

## saslauthd (9)

- `modules/saslauthd/commands/testsaslauthd.sh:19` — dead code — the check above already exits (44) for any non-root
- `modules/saslauthd/commands/testsaslauthd.sh:25` — no argument validation — with $ARG empty or malformed the script
- `modules/saslauthd/commands/testsaslauthd.sh:32` — password is never initialized, so an exported "password"
- `modules/saslauthd/commands/testsaslauthd.sh:47` — this branch reports failure but does not exit — execution falls
- `modules/saslauthd/commands/testsaslauthd.sh:55` — run echoes the full command line, so the plaintext password is
- `modules/saslauthd/hooks/regenerate.sh:7` — restarts saslauthd on every regenerate even though nothing in
- `modules/saslauthd/hooks/update-install-host.sh:31` — unit is written to the RPM-owned path /usr/lib/systemd/system/,
- `modules/saslauthd/hooks/update-install-host.sh:38` — daemon-reload runs after add_service has already enabled and
- `modules/saslauthd/hooks/version.sh:4` — dead code — no "run_hook version" call site exists anywhere in

## srvctl (22)

- `modules/srvctl/command.sh:68` — '$ck == $i' compares a basename to a full path and is never
- `modules/srvctl/command.sh:87` — same dead '$ck == $i' comparison as in the system-unit loop above.
- `modules/srvctl/command.sh:104` — exit_0 runs unconditionally, so service_action failures
- `modules/srvctl/commands/customize.sh:39` — dead v2 branch — $SC_INSTALL_DIR/commands/ does not exist
- `modules/srvctl/commands/fix-owner.sh:8` — this command is a silent no-op — its only action below is
- `modules/srvctl/commands/update-install.sh:50` — replaces the whole config with a single line, dropping
- `modules/srvctl/commands/update-install.sh:71` — unreachable — the no-ARG case already exited above,
- `modules/srvctl/commands/update-install.sh:98` — appends on every run without deduplication —
- `modules/srvctl/commands/version.sh:18` — no 'run_hook version' here (or anywhere), so the
- `modules/srvctl/completion.sh:13` — hardcoded install path, and a full background srvctl run on
- `modules/srvctl/completion.sh:65` — unanchored grep — substring-matches every arg-spec line
- `modules/srvctl/completion.sh:68` — quoted assignment makes arr a ONE-element array, so
- `modules/srvctl/completion.sh:88` — a full-screen MOTD (plus a 1s sleep when the hints file is
- `modules/srvctl/libs/authlib.sh:14` — debug leftover — this echo puts "SC_UID0 true" on
- `modules/srvctl/libs/authlib.sh:53` — stub — a non-root caller only gets this error message
- `modules/srvctl/libs/authlib.sh:65` — $SC_COMMAND_ARGUMENTS is passed as ONE word here and
- `modules/srvctl/libs/authlib.sh:73` — 'exit $?' takes the exit status of debug (0), not
- `modules/srvctl/libs/completionlib.sh:19` — world-writable directory — any local user can replace
- `modules/srvctl/libs/fedoralib.sh:38` — add_service/rm_service below are byte-identical duplicates of
- `modules/srvctl/libs/moduleslib.sh:5` — dead and incomplete — never called from anywhere in the repo,
- `modules/srvctl/libs/networkdlib.sh:123` — bare 'exit' after err exits with status 0, so the
- `modules/srvctl/libs/systemdlib.sh:9` — byte-identical duplicates also live in libs/fedoralib.sh;

## ssh (15)

- `modules/ssh/libs/sshlib.sh:20` — high — key revocation never propagates: only files literally
- `modules/ssh/libs/sshlib.sh:60` — medium — sshd_authorization.sh emits this common file for
- `modules/ssh/libs/sshlib.sh:76` — low — the chown/chmod below run even when neither import
- `modules/ssh/ssh.js:33` — most of the shared datastore-js boilerplate below is dead
- `modules/ssh/ssh.js:105` — dead copy-paste from the opendkim module — never used here.
- `modules/ssh/ssh.js:117` — high — distribution is add-only: stale copies are never
- `modules/ssh/ssh.js:125` — low — fs.mkdirSync without {recursive:true} throws
- `modules/ssh/ssh.js:151` — high — split(".")[1] only matches names with exactly one
- `modules/ssh/ssh.js:192` — low — iterates the cluster-wide containers.json, creating
- `modules/ssh/ssh.js:224` — low — message says srvctl-hosts.conf but the file
- `modules/ssh/ssh.js:235` — low — UserKnownHostsFile is set twice; OpenSSH takes
- `modules/ssh/ssh.js:267` — medium — /srv/<C>/host_key is a self-written cache never
- `modules/ssh/ssh.js:284` — medium — ssh-keyscan exits 0 even with no output
- `modules/ssh/ssh.js:304` — medium — on a down/unreachable host ssh-keyscan still
- `modules/ssh/ssh.js:323` — low — host_ip / hostnet are used unguarded; missing fields

## sshpiperd (11)

- `modules/sshpiperd/build.sh:10` — the script cannot currently complete — it uses
- `modules/sshpiperd/build.sh:18` — inverted test — warns "patch file missing" when the file
- `modules/sshpiperd/build.sh:45` — no-op — the @SRVCTL_INSTALL_DIR token no longer exists in
- `modules/sshpiperd/build.sh:49` — 'run' is undefined in this standalone script (lablib is
- `modules/sshpiperd/hooks/regenerate.sh:13` — if mount_sshpiper fails (e.g. bindfs not installed), this
- `modules/sshpiperd/hooks/update-install-host.sh:38` — legacy-unit cleanup still runs on every update-install.
- `modules/sshpiperd/hooks/update-install-host.sh:41` — the vendored binary is stale (banner 3.1.2.1, reads
- `modules/sshpiperd/hooks/update-install-host.sh:46` — 'run' echoes the command line to stdout (lablib.sh), so the
- `modules/sshpiperd/hooks/update-install-host.sh:51` — the unit is installed but never enabled or started; a fresh
- `modules/sshpiperd/libs/sshpiperlib.sh:25` — hook-time mount only — no fstab entry or .mount
- `modules/sshpiperd/libs/sshpiperlib.sh:28` — hardcodes /var/srvctl3/datastore/users instead of

## static (11)

- `modules/static/hooks/init.sh:17` — 'if $SC_USE_GLUSTER' with an unset variable expands to an
- `modules/static/hooks/update-install-host.sh:18` — 'if $SC_USE_GLUSTER' with an unset variable expands to an
- `modules/static/hooks/update-install-host.sh:32` — runs as root (the sibling default-server runs as nobody)
- `modules/static/hooks/update-install-host.sh:56` — unpinned global npm installs from the network; server.js
- `modules/static/hooks/update-install-host.sh:65` — nothing routes to port 1280 — haproxy's default backend is
- `modules/static/libs/regenerate.sh:15` — iterates the cluster-wide container list, so every host
- `modules/static/server.js:13` — orphaned — nothing routes to :1280 anymore (haproxy's
- `modules/static/server.js:19` — hard-coded /usr/lib/node_modules paths depend on the npm -g
- `modules/static/server.js:38` — the "static." strip reads req.headers.host instead of
- `modules/static/server.js:45` — res.send does not exist on http.ServerResponse (it is
- `modules/static/server.js:61` — docroot built from the unvalidated Host header — '/'

## usersonhost (19)

- `modules/usersonhost/commands/add-publickey.sh:20` — no readonly-datastore guard — an SC_DATASTORE_RO check was
- `modules/usersonhost/commands/add-publickey.sh:28` — the second test is redundant — with an empty ARG, -f "" is
- `modules/usersonhost/commands/add-publickey.sh:52` — on the empty-input path the file was just removed, so this
- `modules/usersonhost/commands/add-reseller.sh:29` — unanchored regex (no ^...$) — any string merely containing a
- `modules/usersonhost/commands/add-user.sh:28` — unanchored regex (no ^...$) — any string merely containing a
- `modules/usersonhost/commands/change-user.sh:47` — unimplemented stub — implement the reassignment (datastore
- `modules/usersonhost/hooks/update-install-host.sh:16` — security review — "ALL ALL=(ALL) NOPASSWD: srvctl.sh *" lets
- `modules/usersonhost/libs/bashlib.sh:26` — dead code — usercfg has no caller anywhere in the tree; if
- `modules/usersonhost/libs/userlib.sh:15` — dead code — create_user_id is only referenced from the
- `modules/usersonhost/libs/userlib.sh:40` — dead code — bash twin of the crate_user_password (sic) in
- `modules/usersonhost/libs/userlib.sh:83` — dead code — everything below the return above is
- `modules/usersonhost/main.js:113` — [high] plaintext password disclosure — this msg() and
- `modules/usersonhost/main.js:141` — mode 0600 on a directory drops the traverse bit — root is
- `modules/usersonhost/main.js:209` — symlink name diverges from the bash twin — here
- `modules/usersonhost/main.js:298` — shell injection — the datastore-supplied name (and
- `modules/usersonhost/user.js:12` — dead code — usercfg (and therefore this script) has no
- `modules/usersonhost/user.js:33` — unused constant, and it aliases SC_DATASTORE_DIR to the
- `modules/usersonhost/user.js:53` — throws (uncaught TypeError, exit 1 instead of the 111
- `modules/usersonhost/user.js:55` — values are written unquoted, so a value containing spaces

## usersonve (14)

- `modules/usersonve/commands/add-user.sh:13` — unlike its siblings this command has no dispatcher guard and no
- `modules/usersonve/commands/add-user.sh:22` — the regex is unanchored — any input containing one valid run
- `modules/usersonve/commands/add-user.sh:40` — if adduser failed above, getent finds nothing and $home stays
- `modules/usersonve/commands/add-user.sh:57` — passwd failures are invisible (stdout and stderr discarded);
- `modules/usersonve/commands/install-crossover.sh:31` — ln -s without -f — re-runs warn "File exists" and cannot update
- `modules/usersonve/commands/install-crossover.sh:47` — unquoted heredoc delimiter — the "$@" inside the generated
- `modules/usersonve/commands/install-qlcplus.sh:24` — release hardcoded to Fedora_38 — stale on newer container
- `modules/usersonve/commands/install-qlcplus.sh:47` — "[[ /home/x/autostart.sh ]]" is a non-empty-string test
- `modules/usersonve/commands/install-qlcplus.sh:66` — created as root with no chown — QLC+ runs as user x and cannot
- `modules/usersonve/commands/install-qlcplus.sh:71` — iterating over ls output breaks on filenames with spaces and
- `modules/usersonve/commands/vnc-desktop.sh:58` — unimplemented branch exits 0 — requesting gnome silently
- `modules/usersonve/commands/vnc-desktop.sh:78` — securitytypes=none (in .vnc/config below) plus this permanently
- `modules/usersonve/commands/vnc-desktop.sh:114` — the generated defaults are immediately thrown away by the
- `modules/usersonve/hooks/update-install-host.sh:9` — misnamed (-host, but VE-side only), and a full dnf update as a

## ve (6)

- `modules/ve/commands/status.sh:11` — missing the standard "[[ $SRVCTL ]] || exit 10" guard —
- `modules/ve/commands/status.sh:13` — help metadata has only the hint line, none of the mandatory
- `modules/ve/commands/status.sh:16` — hint wording nearly duplicates containers' "List container
- `modules/ve/commands/status.sh:24` — for non-root callers du exits 1 on unreadable subdirs; as the
- `modules/ve/hooks/pre-init.sh:9` — missing the standard "[[ $SRVCTL ]] || exit 10" guard.
- `modules/ve/hooks/pre-init.sh:12` — dead code — nothing in the main shell reads SC_VIRT (other

## vncproxy (12)

- `modules/vncproxy/commands/add-vnc-user.sh:22` — regex is unanchored, so any string containing a single
- `modules/vncproxy/commands/add-vnc-user.sh:32` — no privilege check (authorize is never called); a non-root
- `modules/vncproxy/dnf.sh:5` — does not install nmap (needed by vncproxy-restarter.sh), nor
- `modules/vncproxy/start.sh:30` — values are string-interpolated into the INSERT unquoted, and a
- `modules/vncproxy/start.sh:42` — the records file (default 0644, plaintext forward keys) is
- `modules/vncproxy/start.sh:50` — '[[ /bin/vncproxy ]]' tests a non-empty string literal and is
- `modules/vncproxy/vncproxy-restarter.sh:7` — no shebang — direct execution as a systemd ExecStart fails
- `modules/vncproxy/vncproxy-restarter.sh:9` — nmap is not installed by dnf.sh; with the timer active and
- `modules/vncproxy/vncproxy.js:17` — ~80% of this file is dead code copied from datastore tooling
- `modules/vncproxy/vncproxy.js:87` — deterministic, non-cryptographic, unsalted derivation from two
- `modules/vncproxy/vncproxy.js:125` — written with default 0644 in a 0755 dir — every local user can
- `modules/vncproxy/vncproxy.js:140` — runs unconditionally — invoked with no arguments hash()

## wordpress (13)

- `modules/wordpress/commands/install-wordpress.sh:38` — low — no '[[ $SRVCTL ]] || exit 10' guard: run directly with
- `modules/wordpress/commands/install-wordpress.sh:98` — medium — 'run' prints its colored banner on stdout, so the
- `modules/wordpress/commands/install-wordpress.sh:103` — low — unzip without -o: leftovers of an aborted earlier run
- `modules/wordpress/commands/install-wordpress.sh:117` — low — implicit cross-module contract: add_mariadb_db
- `modules/wordpress/commands/install-wordpress.sh:174` — medium — FORCE_SSL_ADMIN with no X-Forwarded-Proto
- `modules/wordpress/commands/install-wordpress.sh:194` — medium — $URI is defined nowhere in the repo, so
- `modules/wordpress/commands/install-wordpress.sh:203` — low — wp-includes/wp-db.php is a deprecated stub since
- `modules/wordpress/commands/install-wordpress.sh:217` — low — reports only php's bare numeric exit code, and the
- `modules/wordpress/commands/install-wordpress.sh:238` — medium — wp-install.php (plaintext admin password in PHP
- `modules/wordpress/scripts/restore-wordpress-password.sh:21` — medium — every failure branch in this script is a bare
- `modules/wordpress/scripts/restore-wordpress-password.sh:33` — low — announces the plaintext password on stdout/logs; HASH
- `modules/wordpress/scripts/restore-wordpress-password.sh:51` — high — "$SC_MDA" is expanded quoted as a single argument
- `modules/wordpress/scripts/restore-wordpress-password.sh:82` — high — the quoted 'show tables' is sent to MySQL as a bare

