# certificates — v3 fact sheet (commit 988c38c)

## Purpose

Host-side X.509 certificate plumbing for the container farm. Provides library functions to
(a) create self-signed wildcard-SAN certificates for a domain (`create_selfsigned_domain_certificate`),
(b) install a host certificate for a local service directory such as `/etc/postfix` with dhparam appended
(`install_service_hostcertificate`), (c) detect admin-installed wildcard certificates under
`/etc/srvctl/cert/*/` and fan them out to matching containers via the datastore cert dir
(`apply_wildcard_certificates` / `check_wildcard_pem`), and (d) validity-check/expiry-prune pem files
(`check_pem`). Also ships `openssl-server-ext.cnf`, the OpenSSL extension file the `ca` module uses to
sign server certificates. The module itself exposes no CLI commands; it is a lib/hook provider consumed
by containers, haproxy, gui, postfix, perdition, named, gluster and openvpn.

## Activation

`module-condition.sh` (modules/certificates/module-condition.sh:3) simply sources
`modules/containers/module-condition.sh`, i.e. the module is enabled exactly when the containers module
is: hostname not `localhost.localdomain`, not itself inside a container (`systemd-detect-virt -c` not
nspawn/lxc), and either (`$SC_HOSTNET` set or `/etc/srvctl/data` exists) with `$HOSTNAME` listed in
`/etc/srvctl/hosts.json` — or `CMD == update-install` with an argument. Same condition is shared by
`datastore` and `letsencrypt`, and (with an `/etc/openvpn` shortcut) by `ca`, so functions from those
modules are available whenever this module is active.

## Commands

| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | module has no `commands/` directory | - |

## Hooks

| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/update-install-host.sh` | `run_hooks update-install-host` from `srvctl update-install` (modules/srvctl/commands/update-install.sh:83) | Guards `[[ $SRVCTL ]] \|\| exit 4`; `mkdir -p /etc/srvctl/cert`; if `$SC_ROOTCA_HOST == $HOSTNAME` calls `root_CA_init` (ca module) with **no argument**; unconditionally calls `install_acme` (letsencrypt module). A large commented-out block (lines 10–31) for importing `/root/crt.pem` is dead code. |
| `hooks/regenerate_certificates.sh` | custom hook name, invoked via `run_hook regenerate_certificates` from haproxy (hooks/regenerate.sh:3, commands/http-redirect.sh:32, commands/https-redirect.sh:31) and named (commands/override-in-address.sh:29) | Single call: `apply_wildcard_certificates`. Not part of the standard pre-/post- lifecycle; only this module provides a hook with this name. |

## Libs

| function | file | notes on external use |
|---|---|---|
| `check_pem PEM` | libs/domaincertlib.sh:4 | Marked `## unused` (line 3) but **used by haproxy** (modules/haproxy/libs/proxylib.sh:9). If the pem expires within 604800 s (7 days) it prints details and **deletes the file** (`rm -rf`, line 34). Always returns 0 regardless of outcome; haproxy relies on the deletion side effect plus its own `-f` re-check. |
| `create_selfsigned_domain_certificate DOMAIN PATH` | libs/domaincertlib.sh:41 | Used by containers (modules/containers/libs/addcontainerlib.sh:93 → `/srv/$C/cert`) and by `install_service_hostcertificate` fallback (servicecertlib.sh:83). Validates any existing `$domain.pem` (checkend 7 days, self-verify, hostname verify), else generates 2048-bit RSA key (passphrase from `new_password`, then stripped), CSR, 3650-day self-signed cert with SAN `DNS:$domain, DNS:*.$domain`, and writes combined `$domain.pem` (key first, then crt) plus `cert.pem`. `exit 46` if a cert exists without its key file (line 109). |
| `install_service_hostcertificate PATH` | libs/servicecertlib.sh:3 | Used by gui (hooks/update-install-host.sh:10), postfix (hooks/update-install-host.sh:12), perdition (libs/install_perdition.sh:13). Searches `/etc/srvctl/cert/` in order: `$SC_COMPANY_DOMAIN` → `${HOSTNAME:3}` (strip 2-char prefix + dot) → `$HOSTNAME` → first matching subdir → self-signed fallback for `$HOSTNAME`. Writes `$PATH/crt.pem` (pem + 1024-bit dhparam appended), `$PATH/key.pem`, optional `$PATH/ca-bundle.pem`; chmod 400 on all three. Caches dhparam at `$src/dhparam`. |
| `check_wildcard_pem PEM` | libs/wildcardcertlib.sh:3 | Echoes the wildcard base domain if the pem's first certificate is unexpired (7-day checkend) and subject is `CN = *.X` (OpenSSL ≤1.x spacing, offset 15) or `CN=*.X` (OpenSSL 3.x, offset 13); otherwise echoes literal `false`. Internal to this module. |
| `apply_wildcard_certificates` | libs/wildcardcertlib.sh:34 | For every `/etc/srvctl/cert/*/*.pem` that is a wildcard cert, copies it to `$SC_DATASTORE_DIR/cert/$c.pem` for every container `c` (from `get cluster container_list`) matching `*.domain` or `domain`. Second copy branch for dot-less container names is dead code (see Bugs). Called by own regenerate_certificates hook only. |

## Config & templates

- No `conf/` directory.
- `openssl-server-ext.cnf` (module root): OpenSSL extension file with a `[ server ]` section
  (`CA:FALSE`, `nsCertType = server`, `nsComment = "Srvctl generated Server Certificate"`,
  `extendedKeyUsage=serverAuth`, `keyUsage = digitalSignature, keyEncipherment`). Never installed
  anywhere; consumed in place by the **ca** module:
  `-extfile $SC_INSTALL_DIR/modules/certificates/openssl-server-ext.cnf -extensions server`
  (modules/ca/libs/calib.sh:97) when signing server certificates for openvpn/gluster.
- `create_selfsigned_domain_certificate` generates ad-hoc `config.txt` / `extfile.txt` / `random.txt`
  inside the target cert path (domaincertlib.sh:140–179); both files are written with 8-space leading
  indentation which the OpenSSL CONF parser tolerates.

## State touched

- Host FS: `/etc/srvctl/cert/` (created by update-install-host hook; per-domain subdirs hold
  `$domain.key`, `$domain.key.org`, `$domain.csr`, `$domain.crt`, `$domain.pem`, `cert.pem`,
  `config.txt`, `extfile.txt`, `dhparam`); service dirs passed by callers (`/etc/postfix`,
  `/etc/perdition`, `/etc/srvctl-gui`) get `crt.pem`, `key.pem`, `ca-bundle.pem` (chmod 400).
- Datastore: writes `$SC_DATASTORE_DIR/cert/$c.pem` (wildcardcertlib.sh:55,61); reads
  `get cluster container_list` via the datastore node helper.
- Container-adjacent: `/srv/$C/cert/` populated via the containers module calling
  `create_selfsigned_domain_certificate`.
- Via delegated calls: `/etc/srvctl/CA/**` (`root_CA_init`, ca module), `/etc/letsencrypt`, `/var/acme`,
  user `acme` (uid 528) and systemd unit `acme-server.service` (`install_acme`, letsencrypt module).
- Log: `$SC_LOG` receives ERROR lines whenever `run openssl …` returns non-zero (lablib.sh:108–110).
- Network: none directly (openssl is local; acme/CA networking belongs to other modules).

## Dependencies

- Core helpers: `msg`, `ntc`, `err`, `run`, `eyif`/`exif` (lablib.sh); `run_hook` dispatch
  (commonlib.sh:85). Note `run` executes `$*` unquoted — several call sites depend on this.
- Other modules (all share the same enable condition, so they are co-active):
  **password** (`new_password`, modules/password/libs/bashlib.sh:3 — node helper),
  **datastore** (`get`, `SC_DATASTORE_DIR`), **ca** (`root_CA_init`, and ca consumes this module's
  `openssl-server-ext.cnf`), **letsencrypt** (`install_acme`), **containers** (module-condition source).
- Consumers of this module: haproxy (`check_pem`), containers (`create_selfsigned_domain_certificate`),
  gui/postfix/perdition (`install_service_hostcertificate`), haproxy/named (regenerate_certificates hook).
- External binaries: `openssl`; `/bin/node` indirectly through `get`/`new_password`.

## Bugs & smells

- **medium** modules/certificates/libs/wildcardcertlib.sh:59 — `[[ $c == "$SC_COMPANY_DOMAIN" ]] && [[ ${c} != *"."* ]]`
  is self-contradictory whenever `SC_COMPANY_DOMAIN` contains a dot (always in real deployments), so the
  copy at line 61 (`$SC_DATASTORE_DIR/cert/$c.$SC_COMPANY_DOMAIN.pem`) never executes; short (dot-less)
  container names silently never receive the company wildcard certificate. First operand was almost
  certainly meant to be `$checked_domain`.
- **medium** modules/certificates/libs/servicecertlib.sh:114-115 — fatal path `err "ERROR Could not locate a certificate…"; exit`
  exits with the status of `err` (0), so a hard failure terminates the whole srvctl run **with exit code 0**,
  masking the failure from update-install wrappers and cron.
- **medium** modules/certificates/libs/domaincertlib.sh:98-102 — `run openssl verify -CAfile "$ssl_pem $ssl_pem"`
  only works because `run` word-splits `$*`; the `[[ "$?" == "2" ]]` branch is labeled "already has a Self
  signed certificate" but exit 2 actually means verification FAILED (verified on OpenSSL 3.5: a self-signed
  pem verifies against itself with exit 0; a CA-signed leaf yields "unable to get local issuer certificate",
  exit 2). Consequence: CA-signed certs take the early-return path without refreshing `cert.pem` or checking
  the key file, and every check of a CA-signed pem logs a spurious ERROR line via `run`→`eyif` into `$SC_LOG`.
- **medium** modules/certificates/libs/domaincertlib.sh:197,204 and modules/certificates/libs/wildcardcertlib.sh:55,61 —
  combined pem files **containing the private key** are created by shell redirection (`cat … > …`) with
  default root umask, i.e. mode 0644 and no chmod; confidentiality relies entirely on parent-directory modes
  set by the unrelated `set_permissions` (commonlib.sh:484-492), which runs only during update-install.
- **medium** modules/certificates/libs/servicecertlib.sh:100 — `openssl dhparam -out … 1024` generates
  1024-bit DH parameters appended to every service `crt.pem`; Logjam-weak and rejected by modern TLS stacks.
- **low** modules/certificates/libs/domaincertlib.sh:3,4-38 — `check_pem` is annotated `## unused` but is
  load-bearing for haproxy (modules/haproxy/libs/proxylib.sh:9); it also returns 0 unconditionally, so the
  caller's `if check_pem` is decorative. Deleting or "fixing" it per the comment breaks haproxy cert pruning.
- **low** modules/certificates/hooks/update-install-host.sh:35 — `root_CA_init` is called with no argument,
  which creates a nameless CA (`/etc/srvctl/CA/ca/.key.pem`, `.crt.pem`, `.srl` — 4096-bit key as hidden
  dot-files, see modules/ca/libs/calib.sh:10-40) that no `create_ca_certificate` caller ever references:
  wasted keygen and a stray unmanaged private key.
- **low** modules/certificates/libs/wildcardcertlib.sh:55 — `$SC_DATASTORE_DIR/cert` is never created by this
  module; with the default read-only datastore (`SC_DATASTORE_RO_USE=true` → gluster path,
  modules/datastore/hooks/pre-init.sh:6-15) or on first run before haproxy/letsencrypt `mkdir -p` it, every
  `cat` fails with "No such file or directory" and wildcard certs are silently not applied (loop status
  usually masks the failure from `run_hook`'s `exif`). In haproxy's own regenerate hook the mkdir
  (modules/haproxy/libs/proxylib.sh:26) runs **after** this hook (modules/haproxy/hooks/regenerate.sh:3-5).
- **low** modules/certificates/hooks/update-install-host.sh:38 — `install_acme` runs here and again from
  letsencrypt's own update-install-host hook (modules/letsencrypt/hooks/update-install-host.sh:8; module
  order is alphabetical, srvctl.sh:72-75), so every update-install performs the acme install twice
  (duplicate `useradd` error noise, double enable/start of acme-server.service).
- **low** modules/certificates/libs/domaincertlib.sh:184-194 — the throwaway key passphrase appears on
  openssl command lines that `run` echoes to the terminal (and `ps`-visible argv), and it is persisted in
  `config.txt` (`output_password`, line 154) left in the cert directory. Mitigated by the key being stripped
  of the passphrase anyway, but it is secret-material leakage into terminal scrollback and on-disk files.

## Polish risks

- `check_pem` (domaincertlib.sh:4-38): must keep returning 0 in every case AND keep the side effect of
  deleting pems that fail `openssl x509 -checkend 604800`; haproxy's `load_certificate_folder_files`
  (proxylib.sh:8-16) depends on delete-then-`-f`-recheck semantics.
- Exit codes: `exit 46` when a domain cert exists without key (domaincertlib.sh:109); `exit 4` guard in
  hooks/update-install-host.sh:5; `exit` (effectively 0 — see Bugs) at servicecertlib.sh:115.
- File layout produced by `create_selfsigned_domain_certificate` (domaincertlib.sh:64-204):
  `$domain.key` (unencrypted), `$domain.key.org` (encrypted), `$domain.csr`, `$domain.crt`,
  `$domain.pem` = **key first, then crt**, `cert.pem` = copy of `$domain.pem`, plus `config.txt`,
  `extfile.txt`; RSA 2048, 3650 days, CN=`$domain`, `emailAddress=webmaster@$domain`,
  SAN `DNS.1=$domain`, `DNS.2=*.$domain`, keyUsage `nonRepudiation, digitalSignature, keyEncipherment,
  dataEncipherment` (comment at 164-165 warns changing this breaks Chrome). Key-first pem order matters:
  consumers (haproxy) load the combined pem.
- `install_service_hostcertificate` search order (servicecertlib.sh:22-90):
  `$SC_COMPANY_DOMAIN` → `${HOSTNAME:3}` → `$HOSTNAME` → first glob-ordered subdir of `/etc/srvctl/cert`
  → generated self-signed for `$HOSTNAME`; output names `crt.pem` (with dhparam appended, servicecertlib.sh:103-105),
  `key.pem`, `ca-bundle.pem`; chmod 400 (:118-123); dhparam cached as `$src/dhparam` (:96-101).
- `check_wildcard_pem` (wildcardcertlib.sh:3-32): echoes the bare domain or the literal string `false`;
  must keep handling both `subject=CN = *.` (offset 15) and `subject=CN=*.` (offset 13) forms.
- Wildcard fan-out target names: `$SC_DATASTORE_DIR/cert/$c.pem` (wildcardcertlib.sh:55); match rules
  `$c == *".$checked_domain"` or `$c == "$checked_domain"` (:52).
- User-visible strings other tooling/operators may grep:
  "Apply wildcard certificates", "Check $i $checked_domain", "Apply wildcard certificate $checked_domain"
  (wildcardcertlib.sh:36,42,46); "create_selfsigned_domain_certificate $1" (domaincertlib.sh:43);
  "Create certificate for $domain." (:136); "$domain has a valid certificate." (:112);
  "Remove $cert_path manually to create a new certificate." + "Certificate files must be: …" + `ls` output
  (:124-126); "Certificate check failed ($reason): $pem" block (:29-33);
  "Host has certificates in $path" / "Host has NO certificate in $path" (servicecertlib.sh:13-15);
  "Could not find certificates for $HOSTNAME. Use a CA signed certificate in production!" (:82);
  "Imported $dom certificate for $path" (:111).
- `openssl-server-ext.cnf` path is hardcoded by the ca module (modules/ca/libs/calib.sh:97):
  `$SC_INSTALL_DIR/modules/certificates/openssl-server-ext.cnf`, section name `server` — moving/renaming
  it breaks server-cert signing for openvpn and gluster. Its `[ server ]` extension content must stay
  semantically identical (nsCertType=server is what openvpn expects).
- Hook name `regenerate_certificates` (with underscore) is invoked by name from haproxy and named modules —
  the filename is API.
- Activation must stay identical to the containers module condition (sourcing semantics), or hooks/libs
  will appear/disappear on hosts where they previously ran.

## v4 notes

- The whole unit is a good candidate for a single `certs.mjs` service: `node:crypto`/openssl child-process
  wrappers with typed results instead of magic exit-code branching (domaincertlib.sh:99) and echo-`false`
  string protocols (wildcardcertlib.sh:31).
- Cert-search fallback chain in `install_service_hostcertificate` is a data-driven priority list — trivial
  to express as an array of candidate dirs in JS; the four near-identical `if ! $found` blocks
  (servicecertlib.sh:20-78) collapse to a loop.
- Duplication to consolidate: expiry checking exists three times (`check_pem`, `check_wildcard_pem`,
  inline in `create_selfsigned_domain_certificate`) with the same 604800-second constant; `install_acme`
  is invoked from two modules' update-install hooks; ca/gluster/openvpn each re-implement
  "root_CA_init + sign server cert" using this module's ext file — a v4 cert authority service should own
  that surface.
- The commented-out `/root/crt.pem` import block (hooks/update-install-host.sh:10-31) and the unused
  `ssl_cab` computation (domaincertlib.sh:86-91) are dead weight; decide intentionally whether root-import
  is a wanted feature before deleting.
- Self-signed generation can drop the encrypt-then-strip passphrase dance entirely
  (domaincertlib.sh:184-194): generate an unencrypted key directly (`openssl genrsa` without `-des3`, or
  `crypto.generateKeyPairSync`), eliminating the password module dependency and the argv/config.txt leaks.
- Fix targets for the rewrite (behavior changes to schedule deliberately, not silently): 2048→3072/4096 or
  ECDSA keys, dhparam 1024→2048+/ffdhe, correct the `$checked_domain` mix-up, proper exit codes on the
  fatal path, and 0600 modes on every file containing key material.
