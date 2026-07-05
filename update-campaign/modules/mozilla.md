# module mozilla — v3 fact sheet (commit 988c38c)

## Purpose
Thunderbird/Mozilla mail-client autoconfiguration. It ships one tiny Node.js HTTP server
(`apps/mozilla-autoconfig-server.js`) that answers **every** request on port 1029 with a
static `clientConfig version="1.1"` XML advertising the host itself as IMAP (993/SSL),
POP3 (995/SSL) and SMTP (465/SSL) server with `password-cleartext` auth (over SSL). The
haproxy module routes `/.well-known/autoconfig/mail/` on every hosted domain to this
backend (`127.0.0.1:1029`, haproxy.js:150,427), so Thunderbird's account auto-setup finds
`http://<domain>/.well-known/autoconfig/mail/config-v1.1.xml` and configures against the
farm host's mail stack (perdition IMAPS/POP3S proxy + postfix SMTPS). 4 files, ~100 lines,
created 2017-09 (0937a07), last touched 2019-01 (deab3f2). No commands, no conf/.

## Activation
`modules/mozilla/module-condition.sh:3` contains only
`source "$SC_INSTALL_DIR/modules/haproxy/module-condition.sh"`, and haproxy's condition
(modules/haproxy/module-condition.sh:4) in turn only sources the **containers** condition.
So mozilla is enabled exactly when containers is, i.e. on container-farm hosts:

- `false` if `$HOSTNAME == localhost.localdomain` (containers/module-condition.sh:3-7)
- `false` inside a container (`systemd-detect-virt -c` = `systemd-nspawn`/`lxc`)
  (containers/module-condition.sh:9-19)
- `true` if the hostname appears quoted in `/etc/srvctl/hosts.json`
  (containers/module-condition.sh:21-25)
- bootstrap escape hatch: `true` when `CMD == update-install` and `$ARG` is set
  (containers/module-condition.sh:28-32)

Evaluated in a subshell (`trtm="$(source …)"`, commonlib.sh:436), cached as
`export SC_USE_MOZILLA=true|false` in `/var/local/srvctl/modules.conf` (root) or
`~/.srvctl/modules.conf`, re-tested only on `update-install`/`test-modules` or when the
cache is missing (commonlib.sh:421-449). Note: mozilla is enabled on **all** farm hosts,
including ones that do not run the mail stack (postfix/perdition activation is broader
policy, but nothing ties mozilla to actual mail service presence).

## Commands
-

(No `commands/` directory.)

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/update-install-host.sh` | `run_hooks update-install-host`, fired from modules/srvctl/commands/update-install.sh:83 during `sc update-install` on a host | Guard `[[ $SRVCTL ]] || exit 4` (line 5), then calls `install_mozilla_autoconfig` (line 8) from libs/install.sh: writes `/etc/systemd/system/mozilla-autoconfig.service`, `systemctl daemon-reload`, then `run systemctl enable/start/status` the service. The file-top comment ("import certificates from root's folder", line 3) is a copy-paste from the certificates/letsencrypt hooks and is wrong. |

Node.js is guaranteed present before the hook runs: update-install.sh:43 does
`[[ -f /bin/node ]] || sc_install nodejs` well before `run_hooks update-install-host`.
There is no regenerate/remove/diagnose hook — install-only, run once per `update-install`.

## Libs
| function | file:line | notes |
|---|---|---|
| `install_mozilla_autoconfig` | libs/install.sh:3-31 | Generates the systemd unit (heredoc-echo, lines 7-23: `Description=Letsencrypt server.`, `ExecStart=/bin/node $SC_INSTALL_DIR/modules/mozilla/apps/mozilla-autoconfig-server.js`, `User=root`/`Group=root`, `Restart=always`, `RestartSec=3`, `WantedBy=multi-user.target`), then `systemctl daemon-reload` (bare, line 26) and `run systemctl enable|start|status --no-pager` (lines 28-30). Idempotent: rerun rewrites the same unit. |

Used **only** by this module's own hook — no other module or core code references
`install_mozilla_autoconfig` (repo-wide grep). Loaded via `load_libs`
(commonlib.sh:47-66) whenever `SC_USE_MOZILLA=true`.

`apps/mozilla-autoconfig-server.js` (not a lib, the runtime payload): builds one static
XML string at startup with `os.hostname()` baked in (js:13,16,24,32), provider id
hardcoded to `D250.hu` (js:10), Thunderbird client-side placeholders `%EMAILDOMAIN%` /
`%EMAILADDRESS%` (js:12-14,20,28,36), then serves it with `200 text/xml` to every
request regardless of method/path (js:47-55), logging `Request.` each time (js:53), and
listens on port 1029 on all interfaces (`listen(1029)`, no bind address, js:57).

## Config & templates
-

(No `conf/` directory. The systemd unit text lives inline in libs/install.sh:7-23 and is
installed to `/etc/systemd/system/mozilla-autoconfig.service`; the XML "template" lives
inline in the .js and is never installed anywhere — it is served from memory.)

## State touched
- **Host files:** writes `/etc/systemd/system/mozilla-autoconfig.service`
  (libs/install.sh:23); the unit embeds the absolute `$SC_INSTALL_DIR` app path.
- **systemd:** `daemon-reload`; enables + starts `mozilla-autoconfig.service`
  (multi-user.target) with `Restart=always` (install.sh:26-29).
- **Network:** root-owned Node process bound to `0.0.0.0:1029` (js:57). firewalld module
  never opens 1029, so external reachability depends on zone config; haproxy consumes it
  via `127.0.0.1:1029` (haproxy.js:427) behind the ACL
  `path_beg /.well-known/autoconfig/mail/` (haproxy.js:150) on hosted domains.
- **Logs:** `Started mozilla-autoconfig-server.js for <hostname>` at start (js:58) and
  `Request.` per hit (js:53) into the journal.
- **Not touched:** no container paths, no datastore keys, no packages of its own.

## Dependencies
- **haproxy module** — condition file sourced by absolute path
  (module-condition.sh:3); also the only thing that makes port 1029 reachable from the
  outside (`thunderbird-backend`, haproxy.js:158-161,426-427). If haproxy's condition
  file moved, mozilla would silently evaluate to disabled.
- **containers module** — transitively provides the actual enable/disable logic.
- **srvctl module** — `update-install` command fires the hook and pre-installs `nodejs`
  (update-install.sh:43,83).
- **perdition/postfix modules (implicit, undeclared)** — the served XML is only truthful
  if the host actually terminates IMAPS 993 / POP3S 995 (perdition/hooks/firewalld.sh:3-4)
  and SMTPS 465 (postfix/hooks/firewalld.sh:4). Nothing enforces this coupling.
- **Core helpers:** `msg` (lablib.sh:23), `run` (lablib.sh:93-115), `run_hook`/`exif`
  (commonlib.sh:85-108, lablib.sh:131), `load_libs` (commonlib.sh:47).
- **External binaries:** `/bin/node`, `systemctl`.

## Bugs & smells
- **medium** modules/mozilla/apps/mozilla-autoconfig-server.js:57 +
  modules/mozilla/libs/install.sh:15-16 — the server binds `0.0.0.0:1029` (no bind
  address given) and runs as `User=root`, although its only consumer is haproxy at
  `127.0.0.1:1029` (haproxy.js:427). Concrete harm: an unnecessary root-owned network
  listener reachable from any interface the firewall zone permits (e.g. the OpenVPN mesh
  / trusted-zone interfaces, cf. firewalld/hooks/diagnose.sh:17) — needless attack
  surface and privilege. The sibling letsencrypt module already does this correctly with
  a dedicated `acme` user (letsencrypt/libs/letsencryptlib.sh:30-31).
- **low** modules/mozilla/libs/install.sh:9 — unit `Description=Letsencrypt server.` is
  copy-pasted from letsencryptlib.sh:24. Harm: `systemctl status mozilla-autoconfig` and
  unit listings show two different services both described as "Letsencrypt server.",
  actively misleading operators during incident triage.
- **low** modules/mozilla/libs/install.sh:30 — the hook's exit status is that of
  `run systemctl status … --no-pager` (last command; `run` returns the child's code,
  lablib.sh:114, and the sourced hook propagates it to `exif`, commonlib.sh:103-104). If
  the service is not "active" at that instant (e.g. port 1029 occupied so node exits and
  the unit is in restart backoff → status exits 3), the **entire** `sc update-install`
  aborts mid-run with only the generic "…/mozilla hook 'update-install-host' failed" —
  all alphabetically-later module hooks (named, nfs, ntp, odoo, opendkim, openvpn, …),
  completion install and `set_permissions` (update-install.sh:83-92) are skipped. `run`'s
  eyif suppression for systemctl (lablib.sh:108) means no explanatory warning is printed.
- **low** modules/mozilla/apps/mozilla-autoconfig-server.js:10 — provider id is
  hardcoded to `"D250.hu"` on every deployment; the branding module is not consulted.
  Harm: third-party operators of srvctl farms serve another organisation's identifier in
  their mail autoconfig; some clients display/log the provider id.
- **low** modules/mozilla/apps/mozilla-autoconfig-server.js:47-55 — every method and
  path gets `200` + the full config XML (no check for
  `/mail/config-v1.1.xml`); combined with the 0.0.0.0 bind, any scanner hitting :1029
  harvests the hostname and mail topology, and via haproxy any URL under
  `/.well-known/autoconfig/mail/` "exists". No concrete breakage, but wrong-by-spec
  and an information leak amplifier for the medium finding above.
- **smell** modules/mozilla/hooks/update-install-host.sh:3 — comment "import
  certificates from root's folder to the system" is a copy-paste from
  certificates/letsencrypt hooks and describes nothing this hook does; misleads readers.
- **smell** modules/mozilla/apps/mozilla-autoconfig-server.js:13,16,24,32 —
  `os.hostname()` is captured once at process start; a hostname change keeps serving the
  old name until restart, and a non-FQDN hostname yields client-unresolvable server
  names. Install-only lifecycle also means there is no path that ever disables or removes
  the service if the module is later turned off.

## Polish risks
- Unit name and path `mozilla-autoconfig.service` in `/etc/systemd/system/`
  (install.sh:23,28-30) — enabled on every production farm host; a rename must handle
  the already-enabled old unit or it stays running forever.
- Port **1029** is a cross-module contract: haproxy.js:427 hardcodes
  `server thunderbird 127.0.0.1:1029` and haproxy.js:150 the ACL
  `path_beg /.well-known/autoconfig/mail/`. Changing either side alone breaks autoconfig.
- App file path `modules/mozilla/apps/mozilla-autoconfig-server.js` is baked into
  installed units via `ExecStart=/bin/node $SC_INSTALL_DIR/...` (install.sh:14); moving
  the file breaks the deployed service (Restart=always crash-loop) until the next
  `update-install` rewrites the unit.
- Served XML is consumed by Thunderbird's parser: keep `Content-Type: text/xml`
  (js:48-50), `<clientConfig version="1.1">` (js:9), the literal placeholder tokens
  `%EMAILDOMAIN%` / `%EMAILADDRESS%` (js:12-14,20,28,36 — Thunderbird substitutes them
  client-side), server types `imap`/`pop3`/`smtp`, ports 993/995/465, `socketType SSL`,
  `authentication password-cleartext` (js:15-37). These must match the perdition/postfix
  reality, not be "modernised" independently.
- Hook filename `hooks/update-install-host.sh` is looked up literally as
  `$dir/hooks/$hook.sh` (commonlib.sh:97).
- Module directory name `mozilla` → cached variable `SC_USE_MOZILLA` persisted in
  modules.conf on production hosts (commonlib.sh:431,447).
- `module-condition.sh` must emit exactly `true` on stdout to enable (commonlib.sh:436-441);
  today it emits whatever the haproxy→containers chain emits, including the
  `update-install + ARG` bootstrap path — keep the delegation semantics.
- Hook exit-status semantics: the sourced hook's status feeds `exif`
  (commonlib.sh:104); the guard `[[ $SRVCTL ]] || exit 4`
  (hooks/update-install-host.sh:5) exits 4 when executed directly.
- `run`-echoed command lines and `systemctl status` output appear in `update-install`
  transcripts (install.sh:28-30), plus `msg "Installing mozilla autoconfig"`
  (install.sh:5) — scripts/humans may grep these.

## v4 notes
- Three near-identical single-purpose Node listeners sit behind haproxy's well-known
  ACLs: acme-server :1028 (letsencrypt), this :1029, datastore server :1030
  (haproxy.js:423-429). v4 should consolidate them into one `.mjs` "well-known" service
  (route table: `/acme-challenge/`, `/autoconfig/mail/config-v1.1.xml`,
  `/srvctl/datastore/`), bound to 127.0.0.1, running as a dedicated non-root user, one
  systemd unit template.
- Inline heredoc systemd-unit generation is duplicated across mozilla/letsencrypt (and
  others); a shared unit-template helper (or packaged unit files) removes the
  copy-paste class of bugs (wrong Description here).
- Make the XML data-driven: provider id / display name from the branding module,
  hostname resolved per request (or from config), advertised protocols derived from
  which mail modules are actually enabled; serve only the exact spec path and 404
  otherwise.
- Activation should be a declared dependency (`requires: haproxy`; arguably
  `requires: perdition|postfix`) instead of sourcing another module's condition file by
  absolute path.
- Consider whether POP3 should still be advertised at all, and add an uninstall/disable
  path (v3 has none — the service outlives the module).
- Coverage matrix currently lists mozilla as "undecided" (update-campaign/000-COVERAGE.md:44).
