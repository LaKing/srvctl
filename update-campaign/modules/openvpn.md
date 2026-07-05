# openvpn — v3 fact sheet (commit 988c38c)

## Purpose

Builds and operates the OpenVPN "hostnet" mesh between cluster hosts: a hub-less full mesh where every host runs one UDP server on port 1101 (`tun-hostnet`, subnet `10.15.$SC_HOSTNET.0/24`) and one client tunnel to every other cluster host (`tun-host$hs`). Certificates come from the srvctl CA module: the `SC_ROOTCA_HOST` mints them, other hosts fetch them over ssh/rsync. The mesh carries the `10.15.x.y` addressing that CLAUDE.md documents ("OpenVPN mesh connects cluster hosts via 10.15.x.y") and that other modules (nfs mounts, ssh known-hosts, datastore hosts file) rely on. The module also teaches the generic `sc <service> <op>` command how to fan a single `openvpn` service name out to all per-tunnel systemd template instances.

## Activation

`module-condition.sh`:
- Line 3-7: if `/etc/openvpn` exists (i.e. the openvpn package/config dir is present, from any prior install) → `echo true`.
- Line 11: otherwise defer to `modules/containers/module-condition.sh`, i.e. enabled when the machine is a cluster host: not `localhost.localdomain`, not itself a container (`systemd-detect-virt -c`), `$HOSTNAME` present in `/etc/srvctl/hosts.json` (with `SC_HOSTNET` or `/etc/srvctl/data` present) — or when running `update-install` with an argument.
- Result is cached as `SC_USE_OPENVPN=true|false` in `modules.conf` by `test_srvctl_modules` (commonlib.sh:404-450); condition scripts run in a `$(source …)` subshell, so `readonly SC_VIRT` in the containers condition does not leak.
- Note: the ca module's condition (modules/ca/module-condition.sh:3) also keys off `-d /etc/openvpn`, so wherever openvpn activates via that path, ca activates too.

## Commands

- (the module has no `commands/` directory; its user-facing surface is the `adjust-service` hook consumed by the generic service command in `modules/srvctl/command.sh`)

## Hooks

| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/pre-init.sh` | `run_hook pre-init` (init.sh:164), every invocation | Defaults `SC_OPENVPN_HOSTNET_SERVER=$HOSTNAME` if unset (line 5). Nothing anywhere in the repo ever reads this variable — dead knob. |
| `hooks/adjust-service.sh` | `run_hook adjust-service` from `modules/srvctl/command.sh:43`, when the dispatched command is a service op | If `$service == openvpn`: on hosts with legacy `openvpn@.service` (line 9-23) iterates `/etc/openvpn/*.conf` and calls `service_action "openvpn@$name" "$op"`; on hosts with split `openvpn-server@`/`openvpn-client@` units (line 25-50) iterates `/etc/openvpn/server/*.conf` then `/etc/openvpn/client/*.conf` and calls `service_action` per instance. Unit instance names are derived by fixed-offset substring (`${c:13: -5}` line 17, `${c:20: -5}` lines 33/43). Empty `$op` means "journalctl since yesterday" per `service_action` (adjust-servicelib.sh:21-25). Returns 0 so `run_hook`'s `exif` passes; the generic command then still runs its own unit search but finds nothing named `openvpn.service` and exits quietly. |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` from `modules/srvctl/commands/update-install.sh:83`, during host (re)install | Full (re)provisioning: `sc_install openvpn` (line 4); abort with `err` + `return` if `SC_ROOTCA_HOST` unset (6-10); `mkdir -p /etc/openvpn` (12); on the root-CA host `init_openvpn_rootca_certificates hostnet` + `usernet` else `grab_openvpn_rootca_certificates` for both nets (15-22); `chmod 600 /etc/openvpn/*.key.pem` (24); generate `/etc/openvpn/dh2048.pem` once (27-30); if `SC_HOSTNET`: write server config, `chown -R openvpn:openvpn /etc/openvpn` (39), enable+restart+status the server unit under whichever unit layout exists (41-55), `firewalld_add_service openvpn-hostnet udp 1101` (57); else `err "Openvpn configuration: SC_HOSTNET undefined"` (61). Then for every other host in `get cluster host_list` (64-95): write client config, symlink it into `/etc/openvpn/client/`, enable+restart+status the client unit, and (fedora-28 branch) attempt a `hostnet-ccd` symlink into `/etc/openvpn/server` (89-92). Ends `return 0` (97) — important because `run_hook` runs `exif` on the hook's status (commonlib.sh:104). |

## Libs

Loaded by `load_libs` (commonlib.sh:47-66) whenever `SC_USE_OPENVPN=true`.

| function | file:line | provides | used elsewhere? |
|---|---|---|---|
| `init_openvpn_create_ca_certificates NET SID` | openvpnlib.sh:3 | Creates server+client certs for `$SID` in `$NET` via ca module's `create_ca_certificate` (self-guarded to the root-CA host). | **Cross-host protocol**: invoked remotely by name through `ssh $SC_ROOTCA_HOST "/bin/srvctl exec-function init_openvpn_create_ca_certificates $NET $HOSTNAME"` (openvpnlib.sh:61, dispatched by run_command's exec-function branch, commonlib.sh:123-128). |
| `init_openvpn_rootca_certificates NET` | openvpnlib.sh:16 | Root-CA host only: `root_CA_init`, root client cert, per-cluster-host server+client certs, then `cat`s the CA cert and this host's own pairs into `/etc/openvpn/$NET-{ca,server,client}.{crt,key}.pem` (38-44). | Only this module's update-install-host hook. |
| `grab_openvpn_rootca_certificates NET` | openvpnlib.sh:48 | Non-CA hosts: verifies ssh reachability of `$SC_ROOTCA_HOST` (ConnectTimeout=1), triggers remote cert creation, rsyncs CA cert + own server/client pairs — each only if the local file is missing (65, 71, 78). `err "CA … connection failed!"` otherwise (86). | Only this module's hook. |
| `install_openvpn` | openvpn_install.sh:4 | Dead code — no caller anywhere in the repo; would `root_CA_init "$HOSTNAME-net"` + create a root client cert. | No. |
| `write_openvpn_hostnet_server_config` | openvpnconfiglib.sh:3 | ccd dirs + `DEFAULT` iroute file, `/etc/openvpn/hostnet-server.conf` heredoc + appended `ifconfig 10.15.$SC_HOSTNET.1 255.255.255.0`, and helper `/etc/openvpn/hostnet-server.sh` (chmod +x). | Only this module's hook. |
| `write_openvpn_client_config HOST` | openvpnconfiglib.sh:60 | Reads `get host $HOST host_ip` / `hostnet` from datastore; skips silently if either missing or HOST==self; writes `/etc/openvpn/hostnet-client-$HOST.conf` + appended `ifconfig 10.15.$hs.$SC_HOSTNET` and `route 10.$hs.0.0 255.255.0.0 10.15.$hs.1`. | Only this module's hook. |

## Config & templates

- No `conf/` directory. All configuration is generated inline by `openvpnconfiglib.sh` heredocs:
  - `/etc/openvpn/hostnet-server.conf` (openvpnconfiglib.sh:15-43): `topology subnet`, `mode server`, `port 1101`, `dev tun-hostnet`, `proto udp`, `status hostnet.log 60` + `status-version 2`, `user/group openvpn`, `persist-tun/-key`, `keepalive 10 60`, `inactive 600`, `verb 4`, `comp-lzo`, `script-security 2`, `cipher AES-256-CBC`, `tls-server`, ca/cert/key/dh paths, `client-config-dir hostnet-ccd`, appended `ifconfig 10.15.$SC_HOSTNET.1 255.255.255.0`.
  - `/etc/openvpn/hostnet-client-$host.conf` (openvpnconfiglib.sh:80-101): `client`, `dev tun-host$hs`, `remote $ip 1101`, `nobind`, `remote-cert-tls server`, same ca + client cert paths, `comp-lzo`, `verb 3`, `cipher AES-256-CBC`, appended `ifconfig`/`route` lines.
  - `/etc/openvpn/hostnet-ccd/DEFAULT` = `iroute 10.15.$SC_HOSTNET.0 255.255.255.0` (openvpnconfiglib.sh:9).
  - `/etc/openvpn/hostnet-server.sh` manual-start helper (openvpnconfiglib.sh:47-52).
- Firewalld service XML `openvpn-hostnet` (udp 1101) generated via the firewalld module (update-install-host.sh:57).

## State touched

- Host paths: `/etc/openvpn/` (confs, `*-ca.crt.pem`, `*-server.{crt,key}.pem`, `*-client.{crt,key}.pem`, `dh2048.pem`, `hostnet-ccd/DEFAULT`, `hostnet-server.sh`, `hostnet.log` status file written by the daemon into its working dir), `/etc/openvpn/server/` + `/etc/openvpn/client/` (symlinked confs, `hostnet-ccd`), `/etc/srvctl/CA/{ca,hostnet,usernet}/…` (via ca module, root-CA host only), `/etc/firewalld/services/openvpn-hostnet.xml`.
- Ownership/permissions: `chown -R openvpn:openvpn /etc/openvpn` (update-install-host.sh:39), `chmod 600 /etc/openvpn/*.key.pem` (24).
- systemd units: `openvpn@hostnet-server`, `openvpn@hostnet-client-$host` (Fedora <28 layout); `openvpn-server@hostnet-server`, `openvpn-client@hostnet-client-$host` (Fedora 28+); enabled + restarted during update-install.
- Datastore keys read: `cluster host_list`, `host <h> host_ip`, `host <h> hostnet` (update-install-host.sh:64, openvpnconfiglib.sh:65-66).
- Network: opens udp/1101; creates `tun-hostnet` + one `tun-host$hs` per peer; addresses `10.15.$SC_HOSTNET.1` (server) and `10.15.$hs.$SC_HOSTNET` (client side), route `10.$hs.0.0/16` via `10.15.$hs.1`. Consumed by nfs (`modules/nfs/libs/nfslib.sh:21-32` pings/mounts `10.15.$hs.1`), ssh (`modules/ssh/ssh.js:251`), datastore hosts output (`modules/datastore/lib.js:901`).
- Outbound: ssh + rsync as root to `$SC_ROOTCA_HOST` (openvpnlib.sh:54-83).

## Dependencies

- Core helpers: `msg`, `ntc`, `err` (lablib.sh), `run` (lablib.sh:93 — note it word-splits `$*`, which `grab_…` relies on for its `$options` string), `run_hook`/`run_hooks` + `exif` (commonlib.sh:85-114).
- Other modules: **ca** (`root_CA_init`, `create_ca_certificate`, `SC_ROOTCA_HOST`, `SC_ROOTCA_DIR`), **datastore** (`get`), **firewalld** (`firewalld_add_service`), **srvctl** (`sc_install` fedoralib.sh:6, `service_action` adjust-servicelib.sh:3), **containers** (module-condition fallback; `SC_HOSTNET` from `/etc/srvctl/host.conf`).
- External binaries: `openvpn`, `openssl`, `ssh`, `rsync`, `systemctl`, `firewall-cmd`, `dnf` (via sc_install), GNU coreutils.
- Cross-host: root ssh trust to `$SC_ROOTCA_HOST`; the CA host must run the same srvctl with `exec-function` and this module enabled.

## Bugs & smells

- **high update-install-host.sh:86** — unit name typo `openvpn-cleint@hostnet-client-$host.service` in the restart: on Fedora 28+ every client tunnel is *enabled* but the restart targets a nonexistent unit, so new or changed client configs never come up during `update-install` (only after reboot or manual restart). Every run also emits a "Unit not found" failure (softened to a warning by `run`/`eyif`).
- **high openvpnconfiglib.sh:13** — the "fedora 28" block `mkdir -p /etc/openvpn/server/hostnet-ccd` (line 12) then writes `DEFAULT` to the *fedora-27* path `/etc/openvpn/hostnet-ccd/DEFAULT` again; `/etc/openvpn/server/hostnet-ccd/DEFAULT` is never created. `openvpn-server@` runs with WorkingDirectory `/etc/openvpn/server`, so `client-config-dir hostnet-ccd` resolves to the empty directory and the `iroute` is never applied on modern hosts.
- **medium update-install-host.sh:89-92** — the intended repair symlink can never happen: the guard `[[ ! -f /etc/openvpn/server/hostnet-ccd ]]` tests `-f` on a directory (always true), and `ln -s /etc/openvpn/hostnet-ccd /etc/openvpn/server` always fails EEXIST because line 12 of openvpnconfiglib.sh already created a real directory of that name (behavior verified with GNU ln). Net effect: per-host loop error noise and the high bug above stays unmitigated. Also, the block only runs inside the peer-host loop, so a single-host cluster never even attempts it.
- **medium openvpnlib.sh:65,71,78** — certificates are only rsynced from the CA host when the local file is *missing*; expired or renewed certs on non-CA hosts are never re-fetched (the CA-side `create_ca_certificate` regenerates expired certs, calib.sh:108-112, but the stale copy in `/etc/openvpn/` stays), so after cert expiry the mesh stays down until someone deletes the local pem files by hand.
- **medium update-install-host.sh:73-87** — when `write_openvpn_client_config` bails because `host_ip`/`hostnet` is missing from the datastore (openvpnconfiglib.sh:69-72), the hook still creates a *dangling* symlink in `/etc/openvpn/client/` (84) and enables the unit (85), leaving a permanently failing enabled service on every boot.
- **medium update-install-host.sh:51,84** — `ln -s` without `-f`/existence guard fails "File exists" on every re-run of `update-install`; line 51 is not even `run`-wrapped, so it fails silently except for stderr. Idempotency noise only (link content stays correct).
- **low hooks/adjust-service.sh:15,31,41** — globs iterate without nullglob; if a conf directory is empty the loop runs once with the literal pattern and calls e.g. `service_action "openvpn-server@*" enable`, which fails against systemctl (the `## must have conf` comments acknowledge but do not guard).
- **low update-install-host.sh:24** — `run chmod 600 /etc/openvpn/*.key.pem` with unmatched glob (e.g. grab failed because CA was unreachable) chmods the literal string and errors, obscuring the real cause.
- **smell hooks/pre-init.sh:5** — `SC_OPENVPN_HOSTNET_SERVER` is defaulted on every invocation and read by nothing in the repo.
- **smell libs/openvpn_install.sh:4** — `install_openvpn` is dead code (no callers repo-wide) with a misleading name relative to `sc_install openvpn`.
- **smell openvpnlib.sh:50,73,80** — `SID` declared but unused (50); progress messages hardcode "usernet" for both nets ("Grabbing usernet $HOSTNAME server certificate…" even when NET=hostnet).
- **smell openvpnconfiglib.sh:65-66** — `ip` and `hs` are not declared `local`, leaking globals from a sourced lib.

## Polish risks

A rewrite must preserve, byte-for-byte where files/units are named:
- Generated file paths and names: `/etc/openvpn/hostnet-server.conf`, `/etc/openvpn/hostnet-client-$host.conf` (openvpnconfiglib.sh:63), `/etc/openvpn/hostnet-ccd/DEFAULT` (:9), `/etc/openvpn/hostnet-server.sh` (:47), `/etc/openvpn/dh2048.pem` (update-install-host.sh:27-29), cert naming scheme `/etc/openvpn/{NET}-ca.crt.pem`, `{NET}-server.{crt,key}.pem`, `{NET}-client.{crt,key}.pem` (openvpnlib.sh:38-44) and CA-side layout `/etc/srvctl/CA/ca/$NET.crt.pem`, `/etc/srvctl/CA/$NET/{server,client}-$HOST.{crt,key}.pem`.
- Config semantics running fleets depend on: `port 1101` + `proto udp` (openvpnconfiglib.sh:19-21,86), `dev tun-hostnet` / `dev tun-host$hs` (:20,:84 — nfs/ssh/datastore address hosts as `10.15.$hs.1` / `10.15.$hs.$SC_HOSTNET`), `ifconfig 10.15.$SC_HOSTNET.1 255.255.255.0` (:43), `ifconfig 10.15.$hs.$SC_HOSTNET 255.255.255.0` and `route 10.$hs.0.0 255.255.0.0 10.15.$hs.1` (:100-101), `cipher AES-256-CBC` + `comp-lzo` + `topology subnet` (peers of mixed versions must still handshake), `user/group openvpn`, `client-config-dir hostnet-ccd`.
- systemd unit instance names: `openvpn@hostnet-server`, `openvpn-server@hostnet-server`, `openvpn-client@hostnet-client-$host` (update-install-host.sh:43-87) — these are enabled persistently on production hosts; renaming orphans enabled units.
- Firewalld service name `openvpn-hostnet` udp 1101 (update-install-host.sh:57) — already-persisted XML on hosts is keyed by this name.
- Cross-host RPC string `/bin/srvctl exec-function init_openvpn_create_ca_certificates $NET $HOSTNAME` (openvpnlib.sh:61): the *function name and argument order* are a wire protocol between hosts that may run different srvctl versions during a rolling upgrade.
- Behavior of `sc openvpn <op>` / `sc <op> openvpn`: fan-out to every conf-derived instance, per-conf `msg` of the instance name, and `return 0` after handling (adjust-service.sh:13-21,29-48) so the generic service search does not double-handle.
- Hook contract: `update-install-host.sh` must end with status 0 (line 97) or `run_hook`'s `exif` aborts the whole `update-install` (commonlib.sh:104); the `SC_ROOTCA_HOST`-unset case errs and returns *success* (lines 6-10) — hardening this into a failure would abort update-install on hosts that previously limped through.
- Activation trigger `-d /etc/openvpn` (module-condition.sh:3) keeps the module (and, via the same test, the ca module) active on already-provisioned hosts even if cluster membership data is absent.

## v4 notes

- The Fedora <28 `openvpn@.service` compatibility branches (adjust-service.sh:9-23, update-install-host.sh:41-46,74-79, the double ccd dirs) target Fedora 27 and earlier; current fleet baseline can almost certainly drop them, collapsing both hooks to the split-unit layout only — but confirm no host still has legacy layout before deleting.
- The cert init/grab pattern (local-if-CA vs ssh+rsync-from-CA, "grab only if missing") is copy-pasted across openvpn, gluster (modules/gluster/hooks/update-install-host.sh, glustercertlib.sh) and certificates modules — a single core "fetch cert material from CA host, with expiry-aware refresh" primitive (good .mjs candidate) would fix the stale-cert bug everywhere at once.
- Config generation is pure templating from datastore values (`host_ip`, `hostnet`, `SC_HOSTNET`, host list) — ideal .mjs candidate: one function computing the desired `/etc/openvpn` tree, one idempotent applier (`ln -sfn`, guarded chmod/chown), then unit reconciliation; would eliminate the EEXIST/idempotency class entirely.
- Crypto/config refresh: `comp-lzo` is deprecated (and compression is a security liability), `AES-256-CBC` should migrate to `data-ciphers AES-256-GCM`, `inactive 600` on a mesh server is questionable, and `status hostnet.log` drops status files into the config/working dir; a v4 template should also write ccd content once to the correct layout path.
- `sc openvpn <op>` fan-out could become generic "service groups" metadata instead of a bespoke hook substring-parsing conf paths with hardcoded offsets (adjust-service.sh:17,33,43).
- Delete dead surface: `libs/openvpn_install.sh`, `SC_OPENVPN_HOSTNET_SERVER` (hooks/pre-init.sh:5) — but grep production `/etc/srvctl/*.conf` for the latter before removal.
- The usernet TODO (openvpnconfiglib.sh:54-56, tcp 1100) has been pending since v3: certificates for `usernet` are minted and distributed (update-install-host.sh:17-21) but no usernet server config is ever written — decide in v4 whether to implement or stop minting.
