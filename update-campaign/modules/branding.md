# branding — v3 fact sheet (commit 988c38c)

## Purpose
Provides the visual/company identity layer for the container farm: company-name variables
(`SC_COMPANY`, `SC_COMPANY_DOMAIN`, `SC_RESELLER_USER` defaults), the shared logo
(`logo.svg`) and `favicon.ico`, a generator for default `index.html` placeholder pages
(used when a new container or static site is created), and a generator for branded HTTP
error pages (`.html` for web servers, raw `.http` responses for haproxy `errorfile`)
written to `/var/www/html` on the host during `update-install`.

## Activation
`modules/branding/module-condition.sh:4` simply sources
`modules/containers/module-condition.sh`, so branding is enabled exactly when the
containers module is enabled:
- false if `HOSTNAME == localhost.localdomain` (containers/module-condition.sh:3-7)
- false inside a container (`systemd-detect-virt -c` is `systemd-nspawn` or `lxc`, lines 12-19)
- true if (`SC_HOSTNET` set or `/etc/srvctl/data` exists) and `$HOSTNAME` appears quoted in
  `/etc/srvctl/hosts.json` (lines 9, 21-25)
- true during `sc update-install <ARG>` (lines 28-32)
- otherwise false

Result is cached as `SC_USE_BRANDING=true|false` in `/var/local/srvctl/modules.conf` /
`~/.srvctl/modules.conf` by `test_srvctl_modules` (commonlib.sh:404-450).

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | module has no `commands/` directory | - |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/pre-init.sh` | `run_hook pre-init` on every invocation (init.sh:164) | Defaults `SC_COMPANY` and `SC_COMPANY_DOMAIN` to `$HOSTNAME`, `SC_RESELLER_USER` to `root`, only if unset (i.e. not provided by `/etc/srvctl/*.conf`) |
| `hooks/post-init.sh` | `run_hook post-init` on every invocation (init.sh:185) | Marks `SC_COMPANY` and `SC_COMPANY_DOMAIN` readonly and exports them (so node.js children see them). Does NOT export or freeze `SC_RESELLER_USER` |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` from `sc update-install` (modules/srvctl/commands/update-install.sh:83) | Prints `msg "Writing Error files in /var/www/html"` then calls `setup_varwwwhtml_error` for codes 400, 403, 404, 408, 414, 500, 501, 502, 503, 504 with fixed English texts |

## Libs
| function | file | notes |
|---|---|---|
| `setup_index_html <name> <dir>` | `libs/brandinglib.sh:3-40` | If `<dir>` exists, writes `<dir>/index.html` (dark page with inlined `logo.svg` and "`<name>` @ `$HOSTNAME`") and copies `favicon.ico` into `<dir>`. **Used by other modules**: containers (`modules/containers/libs/addcontainerlib.sh:63`, into `/srv/$C/rootfs/var/www/html` at add-ve) and static (`modules/static/libs/regenerate.sh:10`, into `/var/srvctl3/storage/static/$dir/html`) |
| `setup_varwwwhtml_error <code> <text>` | `libs/update-install-lib.sh:3-82` | `mkdir -p /var/www/html`; writes `/var/www/html/<code>.html` (branded error page with logo + 31-language "ERROR!" blob) and `/var/www/html/<code>.http` (same page prefixed with a raw `HTTP/1.1 <code> <text>` response header block, consumed by haproxy `errorfile` — haproxy.js:230-243). Used only by this module's `update-install-host` hook |

Both libs are sourced for every enabled-module invocation via `load_libs` (commonlib.sh:47-66, init.sh:177).

## Config & templates
- `logo.svg` — 14.6 KB company logo, inlined verbatim into every generated index/error page (brandinglib.sh:24, update-install-lib.sh:15). Never installed anywhere; read from `$SC_INSTALL_DIR/modules/branding/logo.svg` at generation time.
- `favicon.ico` — copied into each generated docroot (brandinglib.sh:36).
- `html/503.html` — static pre-rendered 503 page; **referenced by no code in the repo** (only coincidental grep hit in haproxy.js for the path `/var/www/html/503.http`); content has drifted from what `setup_varwwwhtml_error` generates (missing trailing `IPHUTHA!` language entry). Dead asset.
- No `conf/` directory. Site config lives in `/etc/srvctl/data/branding.conf` (example: `example-conf/data/branding.conf` defining `SC_COMPANY`, `SC_COMPANY_DOMAIN`), copied to `/etc/srvctl/branding.conf` during update-install (init.sh:102-106) and sourced on every run (init.sh:110-116).

## State touched
- Host: `/var/www/html/` — creates dir; writes `{400,403,404,408,414,500,501,502,503,504}.html` and `.http` (update-install-lib.sh:12,14).
- Container rootfs: `/srv/$C/rootfs/var/www/html/index.html` + `favicon.ico` (via containers module caller).
- Static storage: `/var/srvctl3/storage/static/<container>/html/index.html` + `favicon.ico` (via static module caller).
- Environment: exports `SC_COMPANY`, `SC_COMPANY_DOMAIN` (post-init.sh:6-7) — consumed by node scripts in datastore, haproxy, named, letsencrypt, containers, usersonhost modules and bash libs in certificates, ca, ssh, postfix.
- No systemd units, no datastore keys, no network changes.

## Dependencies
- Core helpers: `msg` (update-install-host.sh:3); hook/lib loading machinery (`run_hook`, `run_hooks`, `load_libs`, `test_srvctl_modules` in commonlib.sh); `$SC_INSTALL_DIR`, `$HOSTNAME`.
- Modules: activation is delegated to the containers module condition; the srvctl module's `update-install` command drives the `update-install-host` hook; haproxy module consumes the generated `.http` files; containers and static modules call `setup_index_html`.
- External binaries: `cat`, `cp`, `mkdir` only (plus `systemd-detect-virt` via the sourced containers condition).

## Bugs & smells
- **low** `hooks/update-install-host.sh:11` — typo "apgain" in `"An internal server error occurred. Please try apgain later."`; this exact text is served to end users on every 500 error via `/var/www/html/500.html` and haproxy's `500.http` errorfile.
- **low** `libs/brandinglib.sh:24,29` — the double quotes around `"$(cat .../logo.svg)"` and `"$_name @ $HOSTNAME"` are inside an unquoted heredoc, so literal `"` characters are emitted into the HTML; every default container/static index page renders stray quote marks around the logo and the title line.
- **low** `hooks/pre-init.sh:9` + `hooks/post-init.sh` — `SC_RESELLER_USER` is defaulted but never exported (post-init.sh exports only `SC_COMPANY`/`SC_COMPANY_DOMAIN`), and its sole consumer `modules/datastore/main.js:34` reads `process.env.SC_RESELLER_USER`, which is therefore always `undefined`; the variable is dead plumbing and any future reseller-permission check built on it would silently see no value.
- **low** `html/503.html:1` — orphaned static asset: no code references it and its language list has drifted from the generated pages (ends at `Kikowaena!`, missing `IPHUTHA!` present in update-install-lib.sh:75); confuses maintenance and invites editing the wrong file.

## Polish risks
- Function names `setup_index_html` and `setup_varwwwhtml_error` are cross-module API (called from `modules/containers/libs/addcontainerlib.sh:63`, `modules/static/libs/regenerate.sh:10`, `hooks/update-install-host.sh:5-15`) — must keep names and positional-arg contracts (`name dir` / `code text`).
- Output file paths `/var/www/html/$code.html` and `/var/www/html/$code.http` (update-install-lib.sh:12,14) — haproxy.js:230-243 hardcodes the `.http` paths; the exact set of codes written (update-install-host.sh:5-15) determines which `errorfile` lines haproxy emits (`fs.existsSync` checks).
- `.http` files must remain a raw, valid HTTP/1.1 response: status line `HTTP/1.1 $_name $_text` and header block `Cache-Control: no-cache` / `Connection: close` / `Content-Type: text/html` / `Retry-After: 60` + blank line (update-install-lib.sh:48-53) — haproxy serves these bytes verbatim.
- Error texts passed per code, including the "apgain" typo if byte-identical output is required (update-install-host.sh:5-15), and the 31-entry multilingual ERROR! blob (update-install-lib.sh:38-40,73-75).
- Generated index.html structure incl. the literal stray quotes (brandinglib.sh:14-34) — a byte-faithful rewrite must reproduce them; title is `$_name`, body text `"$_name @ $HOSTNAME"`.
- `setup_index_html` silently no-ops when the target dir does not exist (brandinglib.sh:11) — callers rely on this (static regenerate loops over all containers).
- `favicon.ico` copied into the docroot (brandinglib.sh:36).
- Env contract after post-init: `SC_COMPANY` and `SC_COMPANY_DOMAIN` are readonly and exported (post-init.sh:3-7), defaulting to `$HOSTNAME` (pre-init.sh:4,6); `SC_RESELLER_USER` defaults to `root` and is intentionally-or-not NOT exported (pre-init.sh:9) — exporting it in a rewrite would change what `modules/datastore/main.js` sees.
- Progress string `msg "Writing Error files in /var/www/html"` (update-install-host.sh:3).
- Activation must stay identical to the containers module (module-condition.sh:4) so `SC_USE_BRANDING` caches the same value as today.

## v4 notes
- The `.html` and `.http` bodies in update-install-lib.sh are a full copy-paste of each other (lines 18-45 vs 54-79); one template function with an optional raw-HTTP-header prefix removes ~35 duplicated lines. Same body also nearly duplicates brandinglib.sh's index page shell — one branded-page template with slots (title, message, extra CSS) covers all three.
- Error-page generation is a pure function `(code, text) -> {html, http}` — an ideal early `.mjs` candidate (no shell state needed beyond `$HOSTNAME` and the asset paths); haproxy's `.http` list and this generator should share one code table instead of two hardcoded lists that can drift (408/414/501 are generated but never wired into haproxy).
- Drop or regenerate `html/503.html`; it is dead and stale.
- Company-identity defaults (`SC_COMPANY*`, `SC_RESELLER_USER`) belong in a central config/defaults layer, not in per-module pre-init/post-init hooks; decide explicitly whether `SC_RESELLER_USER` is API (then export it and use it) or dead (then delete both ends).
- The "source another module's condition" activation pattern (shared with static, firewalld, etc.) argues for declarative module dependencies (`requires: containers`) in the v4 module contract.
- `logo.svg` inlined per page is fine, but v4 could install assets once under `/var/www/html/` and reference them, shrinking each error page from ~15 KB to ~1 KB (behavior change — Phase B only).
