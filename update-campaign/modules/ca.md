# Module ca — v3 fact sheet (commit 988c38c)

## Purpose
Private root-CA management for the cluster. Provides bash library functions to create per-network root CAs (`usernet`, `hostnet`, `gluster`/`glusternet`, arbitrary `$NET`) under `/etc/srvctl/CA`, issue/renew 4096-bit RSA server and client certificates signed by those CAs, export passwordless `.p12` bundles for usernet client certs, and rsync the whole CA directory from the designated CA host (`SC_ROOTCA_HOST`) to other cluster hosts. It has no commands of its own; it is a service library consumed by the `certificates`, `gluster`, and `openvpn` modules.

## Activation
`module-condition.sh`:
- Line 3-7: if directory `/etc/openvpn` exists → `true` (i.e., any host with the openvpn package installed, including — unintentionally — container guests).
- Line 10: otherwise delegates by sourcing `modules/containers/module-condition.sh` (true on real cluster hosts: not `localhost.localdomain`, not inside nspawn/lxc, hostname listed in `/etc/srvctl/hosts.json`, or `CMD=update-install` with an ARG).
- Lines 12-23: dead commented-out historical logic (enable only on `SC_ROOTCA_HOST`).
Condition is evaluated in a command-substitution subshell by `test_srvctl_modules` (commonlib.sh:436), so the `readonly SC_VIRT` set by the sourced containers condition does not leak.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | module ships no `commands/` directory | - |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/pre-init.sh` | every srvctl invocation (before help breakout), after `/etc/srvctl/*.conf` sourced | Defaults: `SC_ROOTCA_DIR=/etc/srvctl/CA` (line 4), `SC_ROOTCA_HOST=$HOSTNAME` (line 6), `SC_ROOTCA_SUBJ="/C=HU/ST=Hungary/L=Budapest/O=SRVCTL-CA"` (line 8) — only if unset by config |
| `hooks/post-init.sh` | every srvctl invocation, after libs loaded | Makes `SC_ROOTCA_HOST`, `SC_ROOTCA_SUBJ`, `SC_ROOTCA_DIR` readonly (lines 4-8). Runs before `containers/hooks/post-init.sh` (alphabetical), which then `export`s `SC_ROOTCA_HOST` |
| `hooks/regenerate.sh` | `run_hook regenerate` (fired by `containers` regenerate command, add-ve, add-ve-user, add-network-ve, codepad add-codepad, regenlib) | Calls `ca_sync` (line 3): no-op msg on the CA host; on other hosts rsyncs the entire remote `/etc/srvctl/CA` into local `/etc/srvctl` |

## Libs
| function (file:line) | provided by | used by |
|---|---|---|
| `root_CA_create net` (calib.sh:6) | creates `$SC_ROOTCA_DIR/ca/$net.key.pem` (genrsa 4096, chmod 600), self-signed `$net.crt.pem` (x509, 3652 days, subj `$SC_ROOTCA_SUBJ/CN=$SC_COMPANY-$net-ca`), serial file `$net.srl` seeded with `02`; each step only if the file is missing | internal (root_CA_init) |
| `root_CA_init net` (calib.sh:46) | only when `SC_ROOTCA_HOST == HOSTNAME`: mkdir `$SC_ROOTCA_DIR/{$1,ca,tmp}`, `chmod -R 600 $SC_ROOTCA_DIR`, `root_CA_create $1`, `rm -fr /etc/srvctl/CA/tmp/*` | certificates/hooks/update-install-host.sh:35 (no arg!), gluster/hooks/update-install-host.sh:16, gluster/libs/glustercertlib.sh:14, openvpn/libs/openvpn_install.sh:12, openvpn/libs/openvpnlib.sh:29 |
| `create_ca_certificate {server\|client} net name` (calib.sh:68) | on CA host only: validates cert/key modulus match and expiry (`-checkend 86400`), deletes and re-issues if INVALID/EXPIRED; issues 4096-bit key + CSR (`CN=$name`) + CA-signed cert (1095 days; server certs get `-extfile .../modules/certificates/openssl-server-ext.cnf -extensions server`); for `client`+`usernet` additionally exports `$SC_ROOTCA_DIR/usernet/client-$name.p12` with empty passphrase | gluster hooks/libs, openvpn/libs/openvpnlib.sh:12-13,31 and openvpn_install.sh:14; also invoked remotely via `srvctl exec-function init_openvpn_create_ca_certificates` (openvpnlib.sh:61) |
| `ca_sync` (netlib.sh:3) | CA host: prints "This is the CA server"; other hosts: if `ssh -n -o ConnectTimeout=1 $SC_ROOTCA_HOST hostname` equals `$SC_ROOTCA_HOST`, `rsync -aze ssh $SC_ROOTCA_HOST:/etc/srvctl/CA /etc/srvctl`, else err; err if `SC_ROOTCA_HOST` empty | ca/hooks/regenerate.sh only |

All four functions are cross-module API — loaded by `load_libs` only when `SC_USE_CA=true`; the consumer modules assume ca is enabled.

## Config & templates
- `openssl-server-ext.cnf` (module root, not `conf/`): `[ server ]` x509 extension block (`CA:FALSE`, `nsCertType=server`, `nsComment="Srvctl generated Server Certificate"`, `extendedKeyUsage=serverAuth`, `keyUsage=digitalSignature, keyEncipherment`). **Never installed and never referenced** — calib.sh:97 uses the byte-identical copy in `modules/certificates/openssl-server-ext.cnf` instead. A third identical copy exists in `modules/letsencrypt/`.
- Site config consumed: `/etc/srvctl/ca.conf` (example: `example-conf/data/ca.conf` sets `SC_ROOTCA_HOST`, `SC_ROOTCA_SUBJ`); `SC_COMPANY` from branding.conf feeds the CA CN.
- No `conf/` directory.

## State touched
- `$SC_ROOTCA_DIR` (default `/etc/srvctl/CA`) on the CA host: `ca/$net.{key,crt}.pem`, `ca/$net.srl`, `$net/{server|client}-$name.{key,crt}.pem`, `usernet/client-$user.p12`, `tmp/*.csr.pem` (wiped via hardcoded `/etc/srvctl/CA/tmp/*`).
- On every non-CA host that runs a `regenerate`: full mirror of the CA host's `/etc/srvctl/CA` (root keys included) under local `/etc/srvctl/CA`.
- Network: outbound ssh (`ConnectTimeout=1`) and rsync-over-ssh to `SC_ROOTCA_HOST` as root.
- No systemd units, no datastore keys, no container paths.

## Dependencies
- Core helpers: `msg`, `ntc`, `err` (lablib.sh), `run` (lablib.sh:93 — note: expands `$*` unquoted, which is what makes the single-string `_ext`/rsync invocations word-split correctly and makes the empty `"$_ext"` argument vanish for client certs).
- Other modules: `certificates` (the ext file at calib.sh:97 lives there); `containers` (module-condition fallback); consumers: `certificates`, `gluster`, `openvpn`, plus `ssh` and `codepad` read/export `SC_ROOTCA_HOST`.
- External binaries: `openssl` (genrsa, req, x509, rsa, md5, pkcs12), `ssh`, `rsync`, `chmod`, `mkdir`, `rm`.
- Env: `SC_COMPANY`, `SC_INSTALL_DIR`, `HOSTNAME`, `SRVCTL`.

## Bugs & smells
- **medium calib.sh:161** — stale `.p12` after re-issue: when an expired/invalid usernet client cert+key are deleted and regenerated (calib.sh:108-119, 125-155), the `.p12` is only created `if [[ ! -f ... .p12 ]]`, so the old bundle containing the expired/mismatched key survives forever; users importing it get a dead identity.
- **medium (security, by design) netlib.sh:12** — `ca_sync` mirrors the *entire* CA directory — root CA private keys, every host/user private key, passwordless `.p12`s — onto every non-CA host on every regenerate; compromise of any cluster host is compromise of the whole PKI. (Empty p12 passphrase is deliberate, calib.sh:175 `-passout pass:` with the passphrase code commented out at 163-179.)
- **medium calib.sh:97** — server-cert signing uses `$SC_INSTALL_DIR/modules/certificates/openssl-server-ext.cnf`, not the module's own identical `modules/ca/openssl-server-ext.cnf` (dead file); ca silently depends on another module's tree — deleting/renaming that file breaks all server cert issuance (openssl x509 fails, cert not created; `run` prints but does not abort).
- **low calib.sh:63** — cleanup hardcodes `rm -fr /etc/srvctl/CA/tmp/*` instead of `$SC_ROOTCA_DIR/tmp/*`; with a customized `SC_ROOTCA_DIR`, CSR temp files are never removed and the rm targets a nonexistent path. Same hardcoding of `/etc/srvctl/CA` in `ca_sync` (netlib.sh:12), so a custom `SC_ROOTCA_DIR` also breaks replication.
- **low calib.sh:46-61** — `root_CA_init` does not validate `$1`; `certificates/hooks/update-install-host.sh:35` calls it with no argument, producing junk hidden CA material `$SC_ROOTCA_DIR/ca/.key.pem`, `.crt.pem` (CN `$SC_COMPANY--ca`), `.srl` on every host where certificates' update-install-host runs on the CA host.
- **low calib.sh:59** — `chmod -R 600` strips the execute bit from every directory in the CA tree (non-traversable for non-root; root only works via DAC override) and re-runs on each init; meanwhile files created afterwards (`.crt.pem`, `.csr.pem`, `.srl`, `.p12` — the last contains a private key) get default-umask 644 and are protected solely by the 600 parent directory.
- **low netlib.sh:10** — reachability test string-compares `ssh $SC_ROOTCA_HOST hostname` output with `$SC_ROOTCA_HOST`; a short-name vs FQDN mismatch yields a false "The CA server ... could not be reached!" and silently skips CA sync.
- **low module-condition.sh:3** — `[[ -d /etc/openvpn ]]` is tested before the containers guard, so the module (and its pre-init/post-init/regenerate hooks) activates inside nspawn containers that happen to have the openvpn package installed.
- **smell calib.sh:22-33** — root CA cert (3652 days) is created only "if missing"; unlike leaf certs there is no expiry check, so after ~10 years issuance continues against an expired CA with no self-healing.
- **smell calib.sh:148** — `run openssl x509 "$_ext" ...` passes a multi-flag string as one quoted argument and an *empty* argument for client certs; it only works because `run` (lablib.sh:105) expands `$*` unquoted. A correctness-minded rewrite of `run` (proper quoting) would break client cert issuance with `openssl: Option unknown option ''`.

## Polish risks
- Defaults a rewrite must keep: `SC_ROOTCA_DIR=/etc/srvctl/CA`, `SC_ROOTCA_HOST=$HOSTNAME`, `SC_ROOTCA_SUBJ="/C=HU/ST=Hungary/L=Budapest/O=SRVCTL-CA"` (pre-init.sh:4-8); readonly promotion in post-init.sh:4-8 (later reassignment must fail the same way).
- On-disk layout and names (other modules rsync these exact paths, e.g. openvpnlib.sh:68-82): `ca/$net.key.pem`, `ca/$net.crt.pem`, `ca/$net.srl` (seed `02`, calib.sh:37), `$net/server-$name.{key,crt}.pem`, `$net/client-$name.{key,crt}.pem`, `usernet/client-$user.p12`, `tmp/$file.csr.pem`.
- Crypto parameters: RSA 4096 (calib.sh:17,131), CA cert 3652 days (calib.sh:30), leaf 1095 days (calib.sh:154), renewal threshold `-checkend 86400` (calib.sh:108), CA CN `$SC_COMPANY-$net-ca` (calib.sh:32), leaf CN `$name` (calib.sh:141), p12 exported with empty passphrase `-passout pass:` (calib.sh:175), key files chmod 600 (calib.sh:19,133).
- Function names/signatures are cross-module API: `root_CA_create`, `root_CA_init`, `create_ca_certificate {server|client} net name`, `ca_sync` — also invoked remotely by name via `srvctl exec-function` chains (openvpnlib.sh:61).
- Silent no-op contract off the CA host: `create_ca_certificate` returns immediately (calib.sh:70-73) and `root_CA_init` does nothing (calib.sh:48) when `SC_ROOTCA_HOST != HOSTNAME` — consumer hooks rely on this being non-fatal.
- Exact user-visible strings: `"This is the CA server"` (netlib.sh:8), `"The CA server $SC_ROOTCA_HOST could not be reached!"` (netlib.sh:14), `"No CA server definded in configs"` including the typo (netlib.sh:18), `"create_ca_certificate error client/server not specified!"` (calib.sh:91), `"$_net certificate for $_u EXPIRED"` (calib.sh:110), `"$_net certificate for $_u INVALID"` (calib.sh:117), `"CA-lib create_ca_certificate $_e $_net $_u"` (calib.sh:100), `"root CA init $1"` (calib.sh:51), `"create $_net ca-key"`/`"create $_net ca-cert"` (calib.sh:13,24), `"create $_file p12"` (calib.sh:169).
- extfile path `$SC_INSTALL_DIR/modules/certificates/openssl-server-ext.cnf` and extension section name `server` (calib.sh:97); moving the ext file or the ca-local copy changes server cert issuance.
- Module activation semantics (`/etc/openvpn` OR containers condition) — other hosts count on ca being active wherever openvpn is, so `ca_sync` runs there on regenerate.
- `ca_sync` destination is `/etc/srvctl` (parent), producing `/etc/srvctl/CA` locally (netlib.sh:12); flag string `-aze ssh` relies on `run`'s word splitting.

## v4 notes
- This module is a natural candidate for a single `ca.mjs` service: pure openssl orchestration with well-defined inputs (net, role, name) and a small state directory — easy to wrap with `node:child_process` and add real error propagation (v3's `run` never actually warns: `eyif` reads `$?` after the `[[ ]]` chain in lablib.sh:108-110, so failures are invisible).
- Deduplicate `openssl-server-ext.cnf` (three identical copies: ca, certificates, letsencrypt) into one shared asset, and make calib reference its own module.
- Parameterize all paths on `SC_ROOTCA_DIR` consistently (calib.sh:63, netlib.sh:12) or drop the variable and hardcode openly.
- Replace full-tree `ca_sync` replication with pull-only distribution of public material + per-host key delivery (openvpnlib.sh:68-82 already does the per-file pattern) — the whole-directory rsync is the module's biggest security liability.
- Regenerate `.p12` whenever the underlying cert is re-issued; consider passphrase support (the commented code at calib.sh:163-195 shows the abandoned intent, including delivery to `$SC_DATASTORE_DIR/users`).
- Add CA-cert expiry checking symmetrical to leaf checking; add argument validation to `root_CA_init`/`root_CA_create`.
- The `certificates` module's no-arg `root_CA_init` call (update-install-host.sh:35) should be fixed or dropped when both modules are polished.
- Commented-out dead code to delete: module-condition.sh:12-23, calib.sh:163-195, 199-206.
