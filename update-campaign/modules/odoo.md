# Module "odoo" — v3 fact sheet (commit 988c38c)

## Purpose
Single-command module that installs the Odoo 14 Community ERP/CRM stack inside a srvctl
VE container. The command body (modules/odoo/commands/install-odoo.sh:12-373) is a
vendored third-party standalone installer — "Copyright: (C) hisi.hr 2019-2021", LGPL v3+,
"installer by m1r0" (install-odoo.sh:13-27, 6) — pasted verbatim under a srvctl command
header. It installs OS packages, creates the `odoo` system user, initializes PostgreSQL,
clones OCA/OCB 14.0, writes `/srv/odoo/odoo14.conf`, builds a python venv at `/srv/venv`,
rigs Apache `ssl.conf` as an HTTPS reverse proxy to ports 8069/8072, installs
`odoo.service`, and enables/restarts the stack. No hooks, no libs, no conf templates.

## Activation
`modules/odoo/module-condition.sh`:
- Sets `container=$HOSTNAME` (module-condition.sh:3).
- If the hostname starts with `mail.` (`${container:0:5} == "mail."`,
  module-condition.sh:6) it echoes `false` — the module is disabled in mail containers.
- Otherwise it delegates by sourcing `$SC_INSTALL_DIR/modules/ve/module-condition.sh`
  (module-condition.sh:11), which echoes `true` iff `systemd-detect-virt -c` reports
  `systemd-nspawn` or `lxc` (modules/ve/module-condition.sh:3-10).

Net effect: enabled inside every srvctl container except `mail.*` ones; always disabled
on hosts. Result cached as `SC_USE_ODOO=true|false` in modules.conf by
`test_srvctl_modules` (commonlib.sh:427-449). The condition runs in a `$( )` subshell
(commonlib.sh:436), so the `SC_VIRT` assignment inside ve/module-condition.sh does not
leak.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| `install-odoo` | "Run scripts that install odoo community and it's basic dependencies." (install-odoo.sh:4; help lines 5-6: "Install the odoo ERP and CRM system." / "Community version, installer by m1r0.") | Root-only (`root_only`, install-odoo.sh:8; plus a second `$USER != root` check exiting 1 at 117-121). Clears screen (147), exports hr_HR.UTF-8 locale (152-154), `dnf update -y` (161), installs deps (162-164), creates `odoo` system user with home `/srv/odoo` (180-186), initdb + pg_hba ident→md5 + UTF-8/hr_HR templates + role `odoo login createdb` (191-207), clones OCB branch 14.0 to `/srv/odoo/odoo14` and makes `/srv/odoo/addons/{symlink,OCA}` (212-252), writes `/srv/odoo/odoo14.conf` (258-281), builds venv `/srv/venv` and pip-installs requirements as user odoo (287-301), patches `/etc/httpd/conf.d/ssl.conf` into a reverse proxy (306-330), writes `/etc/systemd/system/odoo.service` (336-353), enables and restarts postgresql/odoo/httpd (358-369), prints success (373). | Package upgrades of the whole container; new UNIX user/group `odoo`; postgres cluster initialized and templates rewritten; `chown -R odoo:odoo /srv/*` (226, 290); httpd stopped/restarted (363, 369) disrupting anything else served in the container; terminal cleared; locale env, `set -e`, EXIT and ERR traps leak into the running srvctl shell (sourced execution). |

Idempotency guards (re-run skips a block if the marker exists): `/srv/odoo/.bashrc` (180),
`/var/lib/pgsql/data/pg_hba.conf` (191), `/srv/odoo/odoo14` (212), `/srv/venv` (287),
`/etc/httpd/conf.d/ssl.conf.org` (313), `/var/www/html/favicon.ico` (306). The
odoo14.conf and odoo.service heredocs (258, 336) are unconditionally rewritten each run.

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| - | - | (no `hooks/` directory) |

## Libs
- (no `libs/` directory; provides no functions; nothing else in the repo references
  "odoo" — verified by repo-wide grep)

## Config & templates
- (no `conf/` directory). Configuration is generated inline by heredocs:
  `/srv/odoo/odoo14.conf` (install-odoo.sh:258-281; loopback xmlrpc 8069 / longpolling
  8072, `proxy_mode = True`, `db_user = odoo`, `addons_path =
  /srv/odoo/odoo14/addons,/srv/odoo/addons/symlink`, workers 5, memory/time limits),
  Apache proxy block appended to `/etc/httpd/conf.d/ssl.conf` (320-329), and
  `/etc/systemd/system/odoo.service` (336-353; `User=odoo`,
  `ExecStart=/srv/venv/bin/python3 /srv/odoo/odoo14/odoo-bin -c /srv/odoo/odoo14.conf`,
  `Requires=postgresql.service`).

## State touched
All inside the container (module never active on hosts):
- Files/dirs: `/srv/odoo/` (user home; `odoo14/` OCB checkout, `addons/symlink`,
  `addons/OCA`, `odoo14.conf`), `/srv/venv/`, `/etc/httpd/conf.d/ssl.conf` (+ backup
  `ssl.conf.org`), `/var/www/html/index.html` & `favicon.ico` (306-312),
  `/etc/systemd/system/odoo.service`, `/var/lib/pgsql/data/*` (initdb, pg_hba.conf edit).
- Ownership: `chown -R odoo:odoo /srv/*` (226, 290).
- Accounts: system user+group `odoo` (`useradd -m -U -r -d /srv/odoo -s /bin/bash`, 185);
  postgres role `odoo` with LOGIN CREATEDB (205); template0/template1 forced to
  encoding 6 / `hr_HR.UTF-8` collation (203-204).
- systemd units: `postgresql.service`, `odoo.service`, `httpd.service` enabled +
  stop/restart cycle (358-369).
- Network: Odoo bound to 127.0.0.1:8069 and :8072 (269-270); Apache 443 vhost proxies
  `/` and `/longpolling/` to them (323-326). External fetches: dnf repos, npm registry
  (`npm install -g less less-plugin-clean-css`, 164), github.com/OCA/OCB (217), PyPI
  (293-299).
- Datastore keys: none.

## Dependencies
- Core helpers: `root_only` (modules/srvctl/libs/authlib.sh:3-12, exit 44), `msg`
  (lablib.sh). The `root_only` literal within the first 20 lines also hides the command
  from non-root hint listings (commonlib.sh:219). Everything else uses raw
  `echo`/`tput`, not srvctl helpers.
- Other modules: depends on the `ve` module's condition file at
  `$SC_INSTALL_DIR/modules/ve/module-condition.sh` (module-condition.sh:11). Assumes a
  container provisioned like a srvctl VE: `httpd` + `mod_ssl` preinstalled (edits
  `/etc/httpd/conf.d/ssl.conf` at 318-329 without ever installing them) and
  `/var/www/html` present (306-312).
- External binaries: dnf, npm/node, git, useradd, postgresql-setup, psql, su, systemctl,
  tput, sed, python3 (venv/pip). Installed package set at 162-163 (note: includes
  bogus `node`, see Bugs; groups "Development Tools"/"Development Libraries" both still
  resolve in current Fedora comps — verified via `dnf group info`).

## Bugs & smells
- **high install-odoo.sh:162** — the dnf install list contains package name `node`,
  which nothing in Fedora provides (verified: `dnf repoquery --whatprovides node` is
  empty; the binary comes from `nodejs`). dnf aborts the whole transaction, so *none* of
  the dependencies (postgresql-server, devel headers, etc.) get installed; stderr is
  discarded (`>/dev/null 2>&1`) and, per the next finding, the failure doesn't stop the
  script — the install ends with a success message on a machine with no database server.
- **high install-odoo.sh:145 (with srvctl.sh:111, commonlib.sh:164)** — the installer's
  only error handling is `set -e`, but the command file is *sourced* inside the
  `if run_command` condition, a context where bash ignores errexit entirely; and the ERR
  trap that would call `error()` (130-142) is only installed at line 371, *after* all
  work is done. Every failing step (dnf, initdb, git clone, pip) is silently skipped and
  line 373 still prints "System succsesfully installed and services started!". Concrete
  harm: partial/broken installs are indistinguishable from good ones.
- **high install-odoo.sh:152-154, 196, 203-204** — hardcoded Croatian locale
  `hr_HR.UTF-8` is exported for initdb and burned into template0/template1 collation,
  but `glibc-langpack-hr` is never installed (not in the dnf list at 162; no srvctl code
  installs langpacks). On a stock/minimal Fedora container image only C.UTF-8/en_US
  exist, so `postgresql-setup --initdb` fails ("invalid locale settings"), postgres never
  initializes, and the `odoo` role is never created; odoo.service then crash-loops.
- **medium install-odoo.sh:319** — `sed -i -e '218d' /etc/httpd/conf.d/ssl.conf` deletes
  a hard-coded line number assumed to be `</VirtualHost>`. It happens to match the
  current stock mod_ssl file (verified line 218 on a stock Fedora ssl.conf), but any
  packaging shift or prior local edit deletes the wrong line and leaves a duplicate
  `</VirtualHost>`/directives outside the vhost after the append at 320-329 — httpd
  fails config check and every site in the container goes down.
- **medium install-odoo.sh:226, 290** — `chown -R odoo:odoo /srv/*` transfers ownership
  of *everything* under the container's `/srv`, not just the odoo trees it created; any
  co-hosted application data under `/srv` silently changes owner.
- **medium install-odoo.sh:161** — unconditional `dnf update -y` performs a full package
  upgrade of the production container as a hidden side effect of an install command
  (kernel-devel etc. also pulled at 162); can change unrelated service versions without
  operator intent.
- **medium install-odoo.sh:299 (211-217)** — pinned to Odoo/OCB 14.0 (EOL since 2023);
  its `requirements.txt` version pins no longer build against current Fedora
  Python (3.12+), so `pip3 install -r` fails today (silently, per the errexit finding) —
  the module cannot produce a working install on a current container image.
- **low install-odoo.sh:191-207** — the whole postgres block is guarded only by the
  existence of `pg_hba.conf`; if initdb succeeds but role/template configuration fails
  (or postgres was preinstalled), a re-run skips the block forever and the `odoo` role
  is never created. Same non-recoverable-guard pattern for the venv (287) and clone
  (212) blocks.
- **low install-odoo.sh:117-121** — redundant root re-check via `$USER != "root"` after
  `root_only` (8): in cron/systemd contexts where `USER` is unset it spuriously exits 1
  even when UID is 0, and its exit code 1 differs from srvctl's auth-failure code 44
  (authlib.sh:10).
- **low install-odoo.sh:128, 145, 152-154, 371** — because the file is sourced into the
  persistent srvctl shell, `trap cleanup 0`, `trap 'error ${LINENO}' ERR`, the errexit
  option, and the hr_HR.UTF-8 locale exports all leak into the remainder of the srvctl
  process after the command finishes (cleanup itself is dead code — `tempfiles` is never
  populated, 124-127).
- **low install-odoo.sh:291-292** — `$1` inside the `su - odoo -c "python3 -m venv
  /srv/venv $1; $1 source ..."` string expands to `run_command`'s first positional
  parameter, which is always empty (commonlib.sh:116, called bare at srvctl.sh:111). A
  leftover dry-run/comment mechanism from the standalone installer; dead now, breaks the
  venv creation if dispatch ever starts passing arguments.

## Polish risks
A rewrite/polish must preserve exactly:
- Command name `install-odoo` and help block text, including the typo "it's basic
  dependencies" (install-odoo.sh:3-6), and the literal `root_only` token within the
  first 20 lines (install-odoo.sh:8) — hint visibility filtering greps for that string
  (commonlib.sh:219), and authlib's root_only gives exit 44 (authlib.sh:10).
- Module gating: disabled when `$HOSTNAME` starts with `mail.`, else the ve
  container-detection result (module-condition.sh:6-11); condition stdout must be the
  bare word `true`/`false`.
- Startup line `msg "Starting the odoo installer"` (install-odoo.sh:10) and final line
  "System succsesfully installed and services started!" with its typo
  (install-odoo.sh:373) if output compatibility matters; non-root path `exit 1`
  (install-odoo.sh:121).
- Filesystem contract: user `odoo` (system account, home `/srv/odoo`, shell /bin/bash,
  group `odoo`) (185); `/srv/odoo/odoo14` = OCB clone from
  `https://github.com/OCA/OCB.git --depth 1 --branch 14.0` (217);
  `/srv/odoo/addons/symlink` and `/srv/odoo/addons/OCA` (223-225); venv at `/srv/venv`
  (289-291); config at `/srv/odoo/odoo14.conf` with its exact keys/values (258-281) —
  notably `db_user = odoo`, `xmlrpc_port = 8069`, `longpolling_port = 8072`, interfaces
  127.0.0.1, `proxy_mode = True`, `addons_path =
  /srv/odoo/odoo14/addons,/srv/odoo/addons/symlink`, `workers = 5`.
- systemd unit name `odoo.service` and its ExecStart
  `/srv/venv/bin/python3 /srv/odoo/odoo14/odoo-bin -c /srv/odoo/odoo14.conf` (336-353);
  enable set {postgresql, odoo, httpd} (359-361).
- Apache contract: backup file `/etc/httpd/conf.d/ssl.conf.org` as the re-run guard
  (313, 318) and the ProxyPass mappings `/longpolling/ -> :8072`, `/ -> :8069` with
  `retry=0`, ProxyPreserveHost On, inside the SSL vhost (320-329).
- PostgreSQL contract: pg_hba `ident` -> `md5` on host lines (197), role
  `odoo with login createdb` (205), template0/template1 set to encoding 6 /
  hr_HR.UTF-8 (203-204).
- Idempotency marker files listed above (180, 191, 212, 287, 306, 313) — operators may
  rely on re-running the command to "finish" an install without clobbering data.
- Do NOT resurrect intentionally disabled blocks: wkhtmltopdf/MS-fonts install
  (165-175, changelog 41-43) and the OCA addon clones/symlinks (229-249) are commented
  out on purpose.

## v4 notes
- This is vendored third-party code (hisi.hr, LGPL, header at 12-28) glued into a
  command; keep the license header if any of the body survives. Decide first whether
  Odoo 14 support is still wanted at all — it is EOL and unbuildable on current Fedora;
  the honest v4 options are (a) drop the module, or (b) rewrite as a parameterized
  provisioner (odoo version, locale, ports, addons list) — not a mechanical port.
- Natural .mjs shape: a manifest-driven installer (package list, user, git source,
  config/unit templates rendered from `conf/`) with idempotent, individually
  re-checkable steps and real error propagation — replacing the six ad-hoc guard files
  and inert `set -e`.
- Duplication with core: hand-rolled `tput` coloring vs lablib `msg/ntc/prg/err`; the
  `$USER` root check vs `root_only`; the error/trap scaffolding vs `exif/eyif`. The
  `modules/wordpress/commands/install-wordpress.sh` command is the sibling "app
  installer inside a VE" — v4 should extract one shared in-container app-provisioning
  pattern for both.
- The Apache edit should become a dropped-in conf.d fragment (or use srvctl's own
  vhost/proxy machinery) instead of sed-by-line-number surgery on a packaged file.
- Locale must come from configuration (SC_ var or per-container setting), not a
  hardcoded hr_HR.UTF-8 from the original author's environment, and the required
  langpack must be installed alongside.
- The changelog block (37-98) and disabled OCA sections are historical documentation of
  the upstream installer; they belong in module docs, not in the executing script.
